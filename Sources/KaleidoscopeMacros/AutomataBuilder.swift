//
//  AutomataBuilder.swift
//
//
//  Created by Larry Zeng on 11/27/23.
//

import Foundation
import OrderedCollections

// MARK: - Errors

enum GraphError: Error {
    case DuplicatedInputs
    case EmptyMerging(String)
    case IdenticalPriority
    case MergingLeaves
    case OverwriteNonReserved(NodeId)
    case EmptyRoot
    case ShakingError(String)
    case EmptyChildren
    case MergingRangeError
}

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

// MARK: - Graph Input

public struct GraphInput {
    typealias TokenNameType = String

    let token: TokenNameType
    let tokenType: TokenType
    let hir: HIR
    let priority: UInt

    init(token: String, tokenType: TokenType, hir: HIR, priority: UInt? = nil) {
        self.token = token
        self.tokenType = tokenType
        self.hir = hir
        self.priority = priority ?? hir.priority()
    }
}

extension GraphInput: Hashable {
    public static func == (lhs: GraphInput, rhs: GraphInput) -> Bool {
        return lhs.hir == rhs.hir && lhs.token == rhs.token
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hir)
        hasher.combine(token)
    }
}

extension GraphInput: Comparable {
    public static func < (lhs: GraphInput, rhs: GraphInput) -> Bool {
        return lhs.priority < rhs.priority
    }
}

extension GraphInput: CustomStringConvertible {
    public var description: String {
        return "<\(token): \(priority)>"
    }
}

// MARK: - Handle ID Generation

extension Array {
    /// Get the next node id, which is alwayas
    /// euqal to the length of the node list, or
    /// the index of the next appended item
    var nextNodeId: NodeId {
        UInt(count)
    }

    mutating func reserve() -> NodeId where Element == Node? {
        let id = nextNodeId
        append(nil)
        return id
    }

    mutating func reserve(_ node: Node) -> NodeId where Element == Node? {
        let id = nextNodeId
        append(node)
        return id
    }

    mutating func reserve(_ node: Node, _ reserved: NodeId?) throws -> NodeId where Element == Node? {
        guard let index = reserved else {
            return reserve(node)
        }

        let id = Int(index)

        if self[id] == nil {
            self[id] = node
        } else {
            throw GraphError.OverwriteNonReserved(index)
        }
        return index
    }
}

extension OrderedSet {
    /// Get the next info ID, which is always
    /// equal to the length of the info list, or
    /// the index of next appended item
    var nextInputId: InputId {
        count
    }

    /// Get the next end id, which is always
    /// equal to ``nextInfoId``
    var nextEndId: EndsId {
        count
    }

    mutating func reserve(_ input: GraphInput) -> EndsId where Element == GraphInput {
        let id = nextInputId
        append(input)
        return id
    }
}

// MARK: - Automata Graph

public struct PendingMerge: Hashable {
    let waiting: NodeId
    let has: NodeId
    let into: NodeId
}

public struct Merge: Hashable, Equatable {
    let left: NodeId
    let right: NodeId
}

/// Automata representation graph
public struct Graph {
    var nodes: [Node?] = [nil]
    var inputs: OrderedSet<GraphInput> = []
    var hashMap: [UInt: NodeId] = [:]
    var pendingMerges: [PendingMerge] = []
    var merges: [Merge: NodeId] = [:]
    var roots: [NodeId] = []
    var rootId: NodeId?
}

// MARK: - Graph Element Helpers

extension Graph {
    func get(node id: NodeId) -> Node? {
        return nodes[Int(id)]
    }

    func get(input id: EndsId) -> GraphInput {
        return inputs[Int(id)]
    }

    mutating func insertOrPush<I: IntoNode>(_ node: I, _ reserved: NodeId? = nil) throws -> NodeId {
        if let reserved = reserved {
            return try insert(node, reserved)
        } else {
            return reserve(node)
        }
    }

    mutating func insert<I: IntoNode>(_ node: I, _ reserved: NodeId) throws -> NodeId {
        let id = try reserve(node, reserved)

        var ready: [PendingMerge] = []

        for index in (0 ..< pendingMerges.count).reversed() {
            if pendingMerges[index].waiting == reserved {
                ready.append(pendingMerges.remove(at: index))
            }
        }

        for readyMerge in ready.reversed() {
            _ = try mergeKnown(readyMerge.has, readyMerge.waiting, readyMerge.into)
        }

        return id
    }

    mutating func reserve() -> NodeId {
        return nodes.reserve()
    }

    mutating func reserve<I: IntoNode>(_ node: I) -> NodeId {
        return nodes.reserve(node.into())
    }

    mutating func reserve<I: IntoNode>(_ node: I, _ reserved: NodeId?) throws -> NodeId {
        return try nodes.reserve(node.into(), reserved)
    }

    mutating func branch(from node: Node, _ id: NodeId) -> Node.BranchContent {
        switch node {
        case .Branch(let content):
            return content.copy()
        case .Leaf:
            return Node.BranchContent(miss: id)
//        case .Seq(let content):
//            return try! content.toBranch()
        }
    }

    func findMerge(_ left: NodeId, _ right: NodeId) -> NodeId? {
        return merges[.init(left: left, right: right)]
    }

    mutating func setMerge(_ left: NodeId, _ right: NodeId, into: NodeId) {
        merges[.init(left: left, right: right)] = into
        merges[.init(left: left, right: into)] = into
        merges[.init(left: right, right: into)] = into
    }
}

// MARK: - Handle Graph Input

extension Graph {
    public mutating func push(input: GraphInput) throws {
        if inputs.contains(input) {
            throw GraphError.DuplicatedInputs
        }

        let endId = inputs.reserve(input)
        let leafId = try insertOrPush(
            Node.LeafContent(
                endId: endId
            )
        )

        let pathStartId = try push(input.hir, leafId)
        roots.append(pathStartId)
    }

    /// Push a HIR of a token/regex into graph
    ///
    /// - Parameters:
    ///     - hir: High-level intermediate representation
    ///     - then: Node ID to go to if success
    ///     - miss: Node ID to go to if failed
    ///     - reserve: Reserved Node ID to be placed into
    /// - Returns: Node ID of the start of the chain
    mutating func push(_ hir: HIR, _ succ: NodeId, _ miss: NodeId? = nil, _ reserved: NodeId? = nil) throws -> NodeId {
        switch hir {
        case .Empty:
            return succ
        case .Loop(let loop):
            // the loop can exit because of a no match
            // which is still count as successful
            // go to then, or the original miss
            let miss = try miss.map { try merge(succ, $0) } ?? succ

            // create a loop node or reuse the reserved one
            let loopNode: NodeId = reserved ?? reserve()

            // push children that point back to this node
            return try push(loop, loopNode, miss, loopNode)
        case .Maybe(let maybe):
            // allows fail, so miss can be then or the passed down miss
            let miss = try miss.map { try merge(succ, $0) } ?? succ

            // push the children with success, and successful miss
            return try push(maybe, succ, miss, reserved)
        case .Concat(let concat):
            // TODO: optomize continuous literal and class?
            // create shadow to allow chaining
            var succ = succ
            if concat.count != 0 {
                // reverse concat, to allow chaining, succ <- n-1 <- n-2 ... <- 1
                for child in concat[1...].reversed() {
                    // everything in between doesn't allow miss
                    succ = try push(child, succ)
                }

                // push the first to complete the chain, succ <- ... <- 1 <- 0
                succ = try push(concat[0], succ, miss, reserved)
            }

            // if the concat is empty, return succ directly
            return succ
        case .Alternation(let choices):
            // create a branch of things
            var branchContent = Node.BranchContent(miss: miss)

            for childId in try choices.map({ try self.push($0, succ) }) {
                guard let child = get(node: childId) else {
                    throw GraphError.EmptyChildren
                }

                try branchContent.merge(other: branch(from: child, childId), graph: &self)
            }

            let branchId = try reserve(
                branchContent,
                reserved
            )

            return branchId

        case .Literal(let byte):
            return try reserve(
                Node.BranchContent(
                    branches: [byte: succ], miss: miss
                ),
                reserved
            )
        //            return try reserve(Node.SeqContent(seq: bytes, then: succ, miss: miss), reserved)
        case .Class(let classRanges):
            // push a class hir as usual
            let branches: [Node.BranchHit: NodeId] = Dictionary(uniqueKeysWithValues: classRanges.map { ($0, succ) })

            let branchContent = Node.BranchContent(branches: branches, miss: miss)
            return try reserve(branchContent, reserved)
        }
    }
}

// MARK: - Graph Merge

extension Graph {
    /// Merge two nodes given their ids
    mutating func merge(_ a: NodeId, _ b: NodeId) throws -> NodeId {
        // get left node and right node
        if let merge = findMerge(a, b) {
            return merge
        }

        let lhs: Node? = get(node: a)
        let rhs: Node? = get(node: b)

        // work out pending merge and terminal conflicts
        switch (lhs, rhs) {
        case (nil, nil):
            // shouldn't happen
            throw GraphError.EmptyMerging("Something wrong with the internal engine. Please let the developer know.")
        case (nil, _):
            // if either is nil, push to pending merges
            let reservedId = reserve()
            pendingMerges.append(PendingMerge(waiting: a, has: b, into: reservedId))
            setMerge(a, b, into: reservedId)
            return reservedId
        case (_, nil):
            // same as the previous one
            let reservedId = reserve()
            pendingMerges.append(PendingMerge(waiting: b, has: a, into: reservedId))
            setMerge(a, b, into: reservedId)
            return reservedId
        case (.Leaf(let lhs), .Leaf(let rhs)):
            // if they are leaves, choose the one with highest priority
            // and throw when there are priority duplication
            let lhs = get(input: lhs.endId)
            let rhs = get(input: rhs.endId)

            if lhs > rhs {
                return a
            } else if rhs > lhs {
                return b
            } else {
                throw GraphError.IdenticalPriority
            }
        case _:
            // otherwise, follow the following code
            break
        }

        let reserved = reserve()
        setMerge(a, b, into: reserved)
        return try mergeKnown(a, b, reserved)
    }

    mutating func mergeKnown(_ a: NodeId, _ b: NodeId, _ into: NodeId) throws -> NodeId {
        // asserting lhs and rhs are not nil
        guard let lhs = get(node: a), let rhs = get(node: b) else {
            throw GraphError.EmptyMerging("This shouldn't happen.")
        }

        switch (lhs, rhs) {
        case (.Leaf, .Leaf):
            throw GraphError.MergingLeaves
        case _:
            break
        }

        var lhsContent = branch(from: lhs, a)
        let rhsContent = branch(from: rhs, b)

        try lhsContent.merge(other: rhsContent, graph: &self)

        let into = try insert(lhsContent, into)

        return into
    }

    mutating func mergeAllPendings() throws {
        for pending in pendingMerges {
            _ = try mergeKnown(pending.waiting, pending.has, pending.into)
        }

        pendingMerges = []
    }

    mutating func makeRoot() throws -> NodeId {
        var rootId = try insertOrPush(Node.BranchContent())

        for root in roots {
            rootId = try merge(rootId, root)
        }

        self.rootId = rootId

        return rootId
    }
}

// MARK: - Graph Shake

public extension Graph {
    mutating func shake() throws -> NodeId {
        guard let rootId = rootId else {
            throw GraphError.EmptyRoot
        }

        try mergeAllPendings()

        let rootIndex = Int(rootId)

        var marks = [Bool](repeating: false, count: nodes.count)

        let rootNode = get(node: rootId)

        try rootNode?.shake(marks: &marks, index: rootIndex, graph: &self)

        var count = 0
        for (index, mark) in marks.enumerated() {
            if !mark {
                nodes[index] = nil
            } else {
                count += 1
            }
        }

        var newNodes = [Node?](repeating: nil, count: count)

        var indexMapping: [Int?] = (0 ..< nodes.count).map { index in
            if marks[index] {
                count -= 1
                return count
            } else {
                return nil
            }
        }

        let newRootIndex = indexMapping[rootIndex]!

        try! rootNode?.shake(marks: &marks, indexMapping: &indexMapping, newNodes: &newNodes, oldIndex: rootIndex, newIndex: newRootIndex, graph: &self)

        nodes = newNodes
        self.rootId = NodeId(newRootIndex)

        return self.rootId!
    }
}
