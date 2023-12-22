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
    case LongSeqAsBranch
}

// MARK: - Graph Input

/// An input to the graph, serving as a mark of the automata terminal
public struct GraphInput {
    typealias TokenNameType = String

    /// The name of the token, as is in the token enum declaration, which will be used to construct lexer code
    let token: TokenNameType
    /// The type of the token
    let tokenType: TokenType
    /// The high level intermediate representation
    let hir: HIR
    /// The priority of this input/terminal
    let priority: UInt

    /// Create a graph input
    /// - Parameters:
    ///   - token: the token name, as is in the enum declaration
    ///   - tokenType: the token type
    ///   - hir: the high level intermediate representation of how to match for this token
    ///   - priority: the priority of this input/terminal, default to the hir's priority
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

/// Pending merge data type, denoting the merging with a unknown node
public struct PendingMerge: Hashable {
    let waiting: NodeId
    let has: NodeId
    let into: NodeId
}

/// Merge data type, denoting two merged nodes
public struct Merge: Hashable, Equatable {
    let left: NodeId
    let right: NodeId
}

/// Automata representation graph
public struct Graph {
    /// The nodes in this automata graph
    var nodes: [Node?] = [nil]
    /// The terminal informaiton of this graph
    var inputs: OrderedSet<GraphInput> = []
    /// The merges that have not been completed
    var pendingMerges: [PendingMerge] = []
    /// The merge records
    var merges: [Merge: NodeId] = [:]
    /// The tentative roots of this graph
    var roots: [NodeId] = []
    /// The unified root of this graph
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
            return push(node)
        }
    }

    mutating func push<I: IntoNode>(_ node: I) -> NodeId {
        return reserve(node.into())
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
        case .Seq(let content):
            return content.copy().toBranch(graph: &self) // copy to avoid modification
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

// MARK: - Handle Graph HIR Input

extension Graph {
    /// Push a graph terminal into the graph.
    /// - Parameter input: the graph terminal information
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
    ///   - hir: high-level intermediate representation
    ///   - succ: node ID to go to if success
    ///   - miss: node ID to go to if failed
    ///   - reserved: reserved Node ID to be placed into
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
            var buffer: [HIR.ScalarBytes] = []
            var succ = succ

            if concat.count != 0 {
                // reverse concat, to allow chaining, succ <- n-1 <- n-2 ... <- 1
                for child in concat[1...].reversed() {
                    // everything in between doesn't allow miss
                    if case .Literal(let bytes) = child {
                        buffer.append(bytes)
                    } else {
                        if buffer.count > 0 {
                            let bytes = buffer.reversed().reduce(into: []) { $0.append(contentsOf: $1) }
                            succ = try push(.Literal(bytes), succ)
                            buffer.removeAll()
                        }

                        succ = try push(child, succ)
                    }
                }

                // clean up buffer and
                // push the first to complete the chain, succ <- ... <- 1 <- 0
                if case .Literal(let lastBytes) = concat[0] {
                    buffer.append(lastBytes)
                    let bytes = buffer.reversed().reduce(into: []) { $0.append(contentsOf: $1) }
                    succ = try push(.Literal(bytes), succ, miss, reserved)
                } else {
                    if buffer.count > 0 {
                        let bytes = buffer.reversed().reduce(into: []) { $0.append(contentsOf: $1) }
                        succ = try push(.Literal(bytes), succ)
                    }
                    succ = try push(concat[0], succ, miss, reserved)
                }
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

        case .Literal(let bytes):
            return try reserve(
                Node.SeqContent(seq: bytes, then: succ, miss: Node.SeqMiss.toFirst(miss)),
                reserved
            )
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

    mutating func mergeSeq(_ seq: Node.SeqContent, _ other: Node, _ otherId: NodeId) -> Node.SeqContent? {
        switch other {
        case .Branch(let branchContent):
            if seq.miss == nil {
                var loopCount = 0

                // count how many bytes in the prefix is in a loop
                // the count of nice6 and [a-z]*? is 4
                while loopCount < seq.seq.count {
                    if branchContent.contains(seq.seq[loopCount]) == .some(otherId) {
                        loopCount += 1
                    } else {
                        break
                    }
                }

                if let newSeq = seq.split(at: loopCount, graph: &self)?.miss(anytime: otherId) {
                    newSeq.then = try! merge(newSeq.then, otherId)
                    return newSeq
                }
            }
        case .Seq(let otherSeq):
            if let (prefix, miss) = seq.prefix(with: otherSeq) {
                let newSeq = seq.copy().asRemainder(at: prefix.count, graph: &self)
                let newOther = otherSeq.copy().asRemainder(at: prefix.count, graph: &self)

                return try! .init(seq: prefix, then: merge(newSeq, newOther), miss: miss)
            }
        case .Leaf:
            if seq.miss == nil {
                return seq.miss(first: otherId)
            }
        }

        return nil
    }

    mutating func mergeKnown(_ a: NodeId, _ b: NodeId, _ into: NodeId) throws -> NodeId {
        // asserting lhs and rhs are not nil
        guard let lhs = get(node: a), let rhs = get(node: b) else {
            throw GraphError.EmptyMerging("This shouldn't happen.")
        }

        var newSeq: Node.SeqContent? = nil

        switch (lhs, rhs) {
        case (.Leaf, .Leaf):
            throw GraphError.MergingLeaves
        case (.Seq(let seq), _):
            newSeq = mergeSeq(seq.copy(), rhs, b)
        case (_, .Seq(let seq)):
            newSeq = mergeSeq(seq.copy(), lhs, a)
        case _:
            break
        }

        if let newSeq = newSeq {
            return try insertOrPush(newSeq, into)
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
