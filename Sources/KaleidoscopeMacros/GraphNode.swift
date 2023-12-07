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

public enum Node {
    /// the terminal of the graph
    case Leaf(Node.LeafContent)
    /// the state that can lead to multiple states
    case Branch(Node.BranchContent)

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
        }
    }

    func shake(marks: inout [Bool], indexMapping: inout [Int?], newNodes: inout [Node?], oldIndex: Int, newIndex: Int, graph: inout Graph) throws {
        marks[oldIndex] = false

        switch self {
        case .Leaf:
            newNodes[newIndex] = self
        case .Branch(let branchContent):
            var newBranches: [BranchHit: NodeId] = [:]

            for (char, branchId) in branchContent.branches {
                let oldChildIndex = Int(branchId)
                guard let newChildIndex = indexMapping[oldChildIndex] else {
                    throw GraphError.ShakingError("Cannot Find Shaked Index Of Node \(oldChildIndex)")
                }

                newBranches[char] = NodeId(newChildIndex)

                if marks[oldChildIndex] {
                    try graph.get(node: branchId)?.shake(marks: &marks, indexMapping: &indexMapping, newNodes: &newNodes, oldIndex: oldChildIndex, newIndex: newChildIndex, graph: &graph)
                }
            }

            var newMiss: NodeId? = nil
            if let missId = branchContent.miss {
                let oldMissIndex = Int(missId)
                guard let newMissIndex = indexMapping[oldMissIndex] else {
                    throw GraphError.ShakingError("Cannot Find Shaked Index Of Node \(oldMissIndex)")
                }

                newMiss = NodeId(newMissIndex)
                if marks[oldMissIndex] {
                    try graph.get(node: missId)?.shake(marks: &marks, indexMapping: &indexMapping, newNodes: &newNodes, oldIndex: oldMissIndex, newIndex: newMissIndex, graph: &graph)
                }
            }

            newNodes[newIndex] = Node.Branch(.init(branches: newBranches, miss: newMiss))
        }
    }
}

extension Node: IntoNode {
    public func into() -> Node {
        return self
    }
}

extension Node.BranchHit: Comparable {
    public static func < (lhs: ClosedRange<Bound>, rhs: ClosedRange<Bound>) -> Bool {
        return lhs.lowerBound < rhs.lowerBound || (lhs.lowerBound == rhs.lowerBound && lhs.upperBound < rhs.upperBound)
    }

    public func toCode() throws -> String {
        // swift-format-ignore
        guard let lower = Unicode.Scalar(lowerBound)?.escaped(asASCII: true),
              let upper = Unicode.Scalar(upperBound)?.escaped(asASCII: true)
        else {
            throw HIRParsingError.IncorrectCharRange
        }

        if lower == upper {
            return "\"\(lower)\""
        } else {
            return "\"\(lower)\" ... \"\(upper)\""
        }
    }
}

public extension Node {
    typealias BranchHit = HIR.Scalar

//    enum BranchHit: Hashable, ExpressibleByStringLiteral, Comparable {
//        public typealias StringLiteralType = String
//
//        case Range(HIR.Scalar)
//
//        public init(stringLiteral value: String) {
//            self = .Range(value.first!.scalar)
//        }
//
//        public func description() throws -> String {
//            switch self {
//            case .Range(let range):
//                guard let lower = Unicode.Scalar(range.lowerBound)?.escaped(asASCII: true),
//                      let upper = Unicode.Scalar(range.upperBound)?.escaped(asASCII: true)
//                else {
//                    throw HIRParsingError.IncorrectCharRange
//                }
//
//                if lower == upper {
//                    return lower
//                } else {
//                    return "\"\(lower)\" ... \"\(upper)\""
//                }
//            }
//        }
//
//        public static func < (lhs: Node.BranchHit, rhs: Node.BranchHit) -> Bool {
//            switch (lhs, rhs) {
//            case (.Range(let l), .Range(let r)):
//                return l.lowerBound < r.lowerBound || l.upperBound < r.upperBound
//            }
//        }
//    }

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
                    var curr: HIR.Scalar? = sortedHits[index]
                    var currId = combined[curr!]!

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

// public extension Node {
//    struct SeqContent: Hashable, Copy, CustomStringConvertible {
//        var seq: HIR.Scalars
//        var then: NodeId
//        var miss: NodeId?
//
//        func copy() -> Node.SeqContent {
//            return .init(seq: seq, then: then, miss: miss)
//        }
//
//        func into() -> Node {
//            return Node.Seq(self)
//        }
//
//        public var description: String {
//            return seq.map { range in range.map { Unicode.Scalar($0)!.escaped(asASCII: true) }.joined() }.joined()
//        }
//
//        public func toBranch() throws -> Node.BranchContent {
//            guard seq.count == 1 else {
//                throw GraphError.LongSeqToBranch
//            }
//
//            return .init(branches: [seq[0]: then], miss: miss)
//        }
//    }
// }

extension Node: Hashable {
    public static func == (lhs: Node, rhs: Node) -> Bool {
        switch (lhs, rhs) {
        case (.Leaf(let lhsLeaf), .Leaf(let rhsLeaf)):
            return lhsLeaf == rhsLeaf
        case (.Branch(let lhsBranch), .Branch(let rhsBranch)):
            return lhsBranch == rhsBranch
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
//        case .Seq(let seq):
//            seq.hash(into: &hasher)
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
//        case .Seq(let content):
//            return content.description
        }
    }
}
