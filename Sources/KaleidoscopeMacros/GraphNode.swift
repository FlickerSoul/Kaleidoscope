//
//  GraphNode.swift
//
//
//  Created by Larry Zeng on 12/7/23.
//

// MARK: - Grpah Node

public typealias NodeId = UInt
public typealias InputId = Int
public typealias EndsId = InputId

protocol Copy {
    func copy() -> Self
}

protocol IntoNode {
    func into() -> Node
}

func shakeId(marks: inout [Bool], oldId: NodeId, indexMapping: inout [Int?], newNodes: inout [Node?], graph: inout Graph) throws -> NodeId {
    let oldIndex = Int(oldId)
    guard let newIndex = indexMapping[oldIndex] else {
        throw GraphError.ShakingError("Cannot Find Shaked Index Of Node \(oldIndex)")
    }
    let newId = NodeId(newIndex)

    if marks[oldIndex] {
        try graph.get(node: oldId)?.shake(marks: &marks, indexMapping: &indexMapping, newNodes: &newNodes, oldIndex: oldIndex, newIndex: newIndex, graph: &graph)
    }

    return newId
}

/// Graph Node Type
public enum Node {
    /// The terminal of the graph
    case Leaf(Node.LeafContent)
    /// The state that can lead to multiple states
    case Branch(Node.BranchContent)
    /// A sequence of bytes
    case Seq(Node.SeqContent)

    /// Mark used node in order to shake out unused ones.
    func shake(marks: inout [Bool], index: Int, graph: inout Graph) throws {
        marks[index] = true

        switch self {
        case .Leaf:
            break
        case .Branch(let branchContent):
            for branchId in branchContent.branches.values {
                let nodeIndex = Int(branchId)
                if !marks[nodeIndex] {
                    guard let node = graph.get(node: branchId) else {
                        throw GraphError.ShakingError("Node \(branchId) is nil")
                    }

                    try node.shake(marks: &marks, index: nodeIndex, graph: &graph)
                }
            }

            if let missId = branchContent.miss {
                let nodeIndex = Int(missId)
                if !marks[nodeIndex] {
                    guard let node = graph.get(node: missId) else {
                        throw GraphError.ShakingError("Node \(missId) is nil")
                    }

                    try node.shake(marks: &marks, index: nodeIndex, graph: &graph)
                }
            }
        case .Seq(let seqContent):
            let thenIndex = Int(seqContent.then)
            if !marks[thenIndex] {
                guard let thenNode = graph.get(node: seqContent.then) else {
                    throw GraphError.ShakingError("Node \(seqContent.then) is nil")
                }
                try thenNode.shake(marks: &marks, index: thenIndex, graph: &graph)
            }

            if let missId = seqContent.miss?.miss {
                let missIndex = Int(missId)
                if !marks[missIndex] {
                    guard let missNode = graph.get(node: missId) else {
                        throw GraphError.ShakingError("Node \(missId) is nil")
                    }

                    try missNode.shake(marks: &marks, index: missIndex, graph: &graph)
                }
            }
        }
    }

    /// Shake the nodes into the right places.
    func shake(marks: inout [Bool], indexMapping: inout [Int?], newNodes: inout [Node?], oldIndex: Int, newIndex: Int, graph: inout Graph) throws {
        marks[oldIndex] = false

        switch self {
        case .Leaf:
            newNodes[newIndex] = self
        case .Branch(let branchContent):
            var newBranches: [BranchHit: NodeId] = [:]

            for (char, branchId) in branchContent.branches {
                newBranches[char] = try shakeId(marks: &marks, oldId: branchId, indexMapping: &indexMapping, newNodes: &newNodes, graph: &graph)
            }

            var newMiss: NodeId? = nil
            if let missId = branchContent.miss {
                newMiss = try shakeId(marks: &marks, oldId: missId, indexMapping: &indexMapping, newNodes: &newNodes, graph: &graph)
            }

            newNodes[newIndex] = Node.Branch(.init(branches: newBranches, miss: newMiss))
        case .Seq(let seqContent):
            let newThenId = try shakeId(marks: &marks, oldId: seqContent.then, indexMapping: &indexMapping, newNodes: &newNodes, graph: &graph)

            var miss: Node.SeqMiss?
            if let seqMiss = seqContent.miss {
                switch seqMiss {
                case .anytime(let id):
                    miss = try .anytime(shakeId(marks: &marks, oldId: id, indexMapping: &indexMapping, newNodes: &newNodes, graph: &graph))
                case .first(let id):
                    miss = try .first(shakeId(marks: &marks, oldId: id, indexMapping: &indexMapping, newNodes: &newNodes, graph: &graph))
                }
            }

            newNodes[newIndex] = Node.Seq(.init(seq: seqContent.seq, then: NodeId(newThenId), miss: miss))
        }
    }
}

extension Node: IntoNode {
    public func into() -> Node {
        return self
    }
}

public extension Node {
    typealias BranchHit = HIR.ScalarByteRange

    struct BranchContent: Hashable, Copy, IntoNode {
        var branches: [BranchHit: NodeId] = [:]
        var miss: NodeId? = nil

        init(branches: [BranchHit: NodeId] = [:], miss: NodeId? = nil) {
            self.branches = branches
            self.miss = miss
        }

        public static func == (lhs: Node.BranchContent, rhs: Node.BranchContent) -> Bool {
            return lhs.branches == rhs.branches && lhs.miss == rhs.miss
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(branches)
            hasher.combine(miss)
        }

        public func copy() -> Self {
            return .init(
                branches: branches,
                miss: miss
            )
        }

        public func into() -> Node {
            return .Branch(self)
        }

        mutating func merge(other: BranchContent, graph: inout Graph) throws {
            switch (miss, other.miss) {
            case (nil, _):
                // if branch's miss is empty, use other's
                miss = other.miss
            case (.some(let lhs), .some(let rhs)) where lhs != rhs:
                // if both have misses, merge two misses
                miss = try graph.merge(lhs, rhs)
            case _:
                // otherwise, we don't care
                break
            }

            var combined: [Node.BranchHit: NodeId] = branches

            for (hit, hitId) in other.branches {
                // if current branch has the same jump, merge
                // otherwise, merge the jump to the current table
                if let val = combined[hit] {
                    if val == hitId {
                        // if they are the same branch, skip, otherwise
                        // will be an infinite loop
                        continue
                    }
                    combined[hit] = try graph.merge(hitId, val)
                } else {
                    combined[hit] = hitId
                }
            }

            let sortedHits: [Node.BranchHit] = combined.keys.sorted()
            var merged: [Node.BranchHit] = []
            var mergedId: [NodeId] = []

            if sortedHits.count > 0 {
                // add initial thing
                merged.append(sortedHits[0])
                mergedId.append(combined[sortedHits[0]]!)

                // looping through others
                var index = 1

                // go through all sorted hits
                while index < sortedHits.count {
                    // get the one we are merging
                    var curr: HIR.ScalarByteRange? = sortedHits[index]
                    let currId = combined[curr!]!

                    // prepare spaces, and get every ranges that have intersection with curr
                    var stack: [Node.BranchHit] = []
                    var stackId: [NodeId] = []

                    var queued = merged.last

                    // if the queued's upper bound is creater or equal to curr.lowerBound,
                    // they are intersecting. e.g.
                    //  ---- -- -
                    //     -------  or
                    //  -------
                    //        -------
                    while let queuedRes = queued, queuedRes.upperBound >= curr!.lowerBound {
                        stack.append(merged.removeLast())
                        stackId.append(mergedId.removeLast())

                        queued = merged.last
                    }

                    while stack.count > 0 {
                        guard let currUnwrapped = curr else {
                            throw GraphError.MergingRangeError
                        }

                        let comp = stack.removeLast()
                        let compId = stackId.removeLast()

                        if comp.lowerBound < currUnwrapped.lowerBound {
                            let left = comp.lowerBound ... (currUnwrapped.lowerBound - 1)
                            merged.append(left)
                            mergedId.append(compId)

                            let mid = currUnwrapped.lowerBound ... comp.upperBound
                            merged.append(mid)
                            try mergedId.append(graph.merge(currId, compId))

                            if comp.upperBound < currUnwrapped.upperBound {
                                curr = comp.upperBound + 1 ... currUnwrapped.upperBound
                            } else {
                                curr = nil
                            }
                        } else if currUnwrapped.lowerBound <= comp.lowerBound {
                            if currUnwrapped.lowerBound < comp.lowerBound {
                                let left = currUnwrapped.lowerBound ... comp.lowerBound - 1
                                merged.append(left)
                                mergedId.append(currId)
                            }

                            let mid = comp
                            merged.append(mid)
                            try mergedId.append(graph.merge(currId, compId))

                            if comp.upperBound < currUnwrapped.upperBound {
                                curr = comp.upperBound + 1 ... currUnwrapped.upperBound
                            } else {
                                curr = nil
                            }
                        }
                    }

                    if let curr = curr {
                        merged.append(curr)
                        mergedId.append(currId)
                    }

                    index += 1
                }
            }

            branches = Dictionary(uniqueKeysWithValues: zip(merged, mergedId))
        }

        func contains(_ val: HIR.ScalarByte) -> NodeId? {
            for (range, nodeId) in branches {
                if range.contains(val) {
                    return nodeId
                }
            }

            return nil
        }
    }
}

extension Node.BranchContent: CustomStringConvertible {
    public var description: String {
        return "{" +
            branches.map { key, val in
                "\(key) => \(val)"
            }.joined(separator: ", ") +
            (miss == nil ? "" : " | _ => \(miss!)") +
            "}"
    }
}

public extension Node {
    struct LeafContent: Hashable, Copy, IntoNode {
        var endId: EndsId

        init(endId: EndsId) {
            self.endId = endId
        }

        public static func == (lhs: Node.LeafContent, rhs: Node.LeafContent) -> Bool {
            return lhs.endId == rhs.endId
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(endId)
        }

        public func copy() -> Self {
            return .init(endId: endId)
        }

        public func into() -> Node {
            return .Leaf(self)
        }
    }
}

extension Node.LeafContent: CustomStringConvertible {
    public var description: String {
        return "@\(endId)"
    }
}

public extension Node {
    enum SeqMiss: Hashable {
        case first(NodeId)
        case anytime(NodeId)

        var miss: NodeId {
            switch self {
            case .first(let id), .anytime(let id):
                return id
            }
        }

        var anytimeMiss: NodeId? {
            switch self {
            case .anytime(let id):
                return id
            case _:
                return nil
            }
        }

        static func toFirst(_ id: NodeId?) -> Self? {
            if let id = id {
                return .first(id)
            }
            return nil
        }

        static func toAnytime(_ id: NodeId?) -> Self? {
            if let id = id {
                return .anytime(id)
            }
            return nil
        }
    }

    class SeqContent: Copy, IntoNode, Hashable, CustomStringConvertible {
        var seq: HIR.ScalarBytes
        var then: NodeId
        var miss: SeqMiss?

        required init(seq: HIR.ScalarBytes, then: NodeId, miss: SeqMiss? = nil) {
            self.seq = seq
            self.then = then
            self.miss = miss
        }

        func copy() -> Self {
            return .init(seq: seq, then: then, miss: miss)
        }

        func into() -> Node {
            return Node.Seq(self)
        }

        public func toBranch(graph: inout Graph) -> Node.BranchContent {
            let hit = seq.remove(at: 0)
            let missId = miss?.miss

            let thenId: NodeId
            if seq.count == 0 {
                thenId = then
            } else {
                thenId = graph.push(self)
            }

            return .init(branches: [hit.scalarByteRange: thenId], miss: missId)
        }

        public func asRemainder(at: Int, graph: inout Graph) -> NodeId {
            seq = Array(seq[at ..< seq.count])

            if seq.count == 0 {
                return then
            } else {
                return graph.push(self)
            }
        }

        public func split(at: Int, graph: inout Graph) -> SeqContent? {
            switch at {
            case 0:
                return nil
            case seq.count:
                return self
            case _:
                break
            }

            let current = seq[0 ..< at]
            let next = seq[at ..< seq.count]

            let nextMiss: Node.SeqMiss?
            if let miss = miss?.anytimeMiss {
                nextMiss = .anytime(miss)
            } else {
                nextMiss = nil
            }

            let nextId = graph.push(Self(seq: Array(next), then: then, miss: nextMiss))

            seq = Array(current)
            then = nextId

            return self
        }

        public func miss(first val: NodeId?) -> Self {
            if let val = val {
                miss = .first(val)
            } else {
                miss = nil
            }
            return self
        }

        public func miss(anytime val: NodeId?) -> Self {
            if let val = val {
                miss = .anytime(val)
            } else {
                miss = nil
            }

            return self
        }

        public func prefix(with other: SeqContent) -> (HIR.ScalarBytes, SeqMiss)? {
            var count = 0
            while count < other.seq.count && count < seq.count {
                if other.seq[count] == seq[count] {
                    count += 1
                } else {
                    break
                }
            }

            if count == 0 {
                return nil
            }

            let newSeq = Array(seq[0 ..< count])

            switch (miss, other.miss) {
            case (nil, .some(let newMiss)), (.some(let newMiss), nil):
                return (newSeq, newMiss)
            case _:
                return nil
            }
        }

        public static func == (lhs: Node.SeqContent, rhs: Node.SeqContent) -> Bool {
            return lhs.seq == rhs.seq && lhs.then == rhs.then && lhs.miss == rhs.miss
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(seq)
            hasher.combine(then)
            hasher.combine(miss)
        }

        public var description: String {
            var des = "`\(seq.map { Unicode.Scalar($0)!.escaped(asASCII: true) }.joined())` => \(then)"
            if let miss = miss {
                des += " | _ => \(miss)"
            }

            return des
        }
    }
}

extension Node: Hashable {
    public static func == (lhs: Node, rhs: Node) -> Bool {
        switch (lhs, rhs) {
        case (.Leaf(let lhsLeaf), .Leaf(let rhsLeaf)):
            return lhsLeaf == rhsLeaf
        case (.Branch(let lhsBranch), .Branch(let rhsBranch)):
            return lhsBranch == rhsBranch
        case (.Seq(let lhsSeq), .Seq(let rhsSeq)):
            return lhsSeq == rhsSeq
        case _:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .Leaf(let leaf):
            leaf.hash(into: &hasher)
        case .Branch(let branch):
            branch.hash(into: &hasher)
        case .Seq(let seq):
            seq.hash(into: &hasher)
        }
    }
}

extension Node: CustomStringConvertible {
    public var description: String {
        switch self {
        case .Leaf(let content):
            return content.description
        case .Branch(let content):
            return content.description
        case .Seq(let content):
            return content.description
        }
    }
}
