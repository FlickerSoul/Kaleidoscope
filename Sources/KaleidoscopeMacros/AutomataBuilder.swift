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
    case EmptyMerging
    case IdenticalPriority
    case MergingLeaves
    case OverwriteNonReserved
    case EmptyRoot
    case ShakingError
    case EmptyChildren
}

// MARK: - Callback Types

public protocol GetResult {
    func get<R>() throws -> R?
}

public enum CallbackResult<T> {
    case skip
    case match(T)
    case error(Error)
}

extension CallbackResult: GetResult {
    public func get<R>() throws -> R? {
        switch self {
        case .skip: return nil
        case .match(let res): return (res as! R)
        case .error(let err): throw err
        }
    }
}

public typealias MatchCallbackType = () -> GetResult
public typealias ExactMatchCallbackType<T> = () -> CallbackResult<T>

// MARK: - Grpah Node

public typealias NodeId = UInt
public typealias InputId = UInt
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

    func shake<T>(marks: inout [Bool], graph: inout Graph<T>) {
        switch self {
        case .Leaf:
            break
        case .Branch(let branchContent):
            for branchId in branchContent.branches.values {
                let nodeIndex = Int(branchId)
                if !marks[nodeIndex] {
                    marks[nodeIndex] = true
                    graph.get(node: branchId)?.shake(marks: &marks, graph: &graph)
                }
            }

            if let missId = branchContent.miss {
                let nodeIndex = Int(missId)
                if !marks[nodeIndex] {
                    marks[nodeIndex] = true
                    graph.get(node: missId)?.shake(marks: &marks, graph: &graph)
                }
            }
        }
    }

    func shake<T>(marks: inout [Bool], indexMapping: inout [Int?], newNodes: inout [Node?], oldIndex: Int, newIndex: Int, graph: inout Graph<T>) throws {
        marks[oldIndex] = false

        switch self {
        case .Leaf:
            newNodes[newIndex] = self
        case .Branch(let branchContent):
            newNodes[newIndex] = Node.Branch(.init())

            var newBranches: [Character: NodeId] = [:]

            for (char, branchId) in branchContent.branches {
                let oldChildIndex = Int(branchId)
                guard let newChildIndex = indexMapping[oldChildIndex] else {
                    throw GraphError.ShakingError
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
                    throw GraphError.ShakingError
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

public extension Node {
    struct BranchContent: Hashable, Copy, IntoNode {
        var branches: [Character: NodeId] = [:]
        var miss: NodeId? = nil

        init(branches: [Character: NodeId] = [:], miss: NodeId? = nil) {
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

        mutating func merge<TokenType>(other: BranchContent, graph: inout Graph<TokenType>) {
            switch (miss, other.miss) {
            case (nil, _):
                // if branch's miss is empty, use other's
                miss = other.miss
            case (.some(let lhs), .some(let rhs)):
                // if both have misses, merge two misses
                miss = try! graph.merge(lhs, rhs)
            case _:
                // otherwise, we don't care
                break
            }

            // go through each jump char in the jump table
            for (hit, hitId) in other.branches {
                // if current branch has the same jump, merge
                // otherwise, merge the jump to the current table
                if let val = branches[hit] {
                    branches[hit] = try! graph.merge(hitId, val)
                } else {
                    branches[hit] = hitId
                }
            }
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
        }
    }
}

// MARK: - Graph Input

public struct GraphInput<T: Hashable> {
    let token: T
    let hir: HIR
    let callback: MatchCallbackType?
    let priority: UInt

    init(token: T, hir: HIR, callback: MatchCallbackType? = nil, priority: UInt? = nil) {
        self.token = token
        self.hir = hir
        self.callback = callback
        self.priority = priority ?? hir.priority()
    }
}

extension GraphInput: Hashable {
    public static func == (lhs: GraphInput<T>, rhs: GraphInput<T>) -> Bool {
        return lhs.hir == rhs.hir && lhs.token == rhs.token
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hir)
        hasher.combine(token)
    }
}

extension GraphInput: Comparable {
    public static func < (lhs: GraphInput<T>, rhs: GraphInput<T>) -> Bool {
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
            throw GraphError.OverwriteNonReserved
        }
        return index
    }
}

extension OrderedSet {
    /// Get the next info ID, which is always
    /// equal to the length of the info list, or
    /// the index of next appended item
    var nextInputId: InputId {
        UInt(count)
    }

    /// Get the next end id, which is always
    /// equal to ``nextInfoId``
    var nextEndId: EndsId {
        UInt(count)
    }

    mutating func reserve<T>(_ input: GraphInput<T>) -> EndsId where Element == GraphInput<T> {
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
public struct Graph<T> where T: Hashable {
    var nodes: [Node?] = [nil]
    var inputs: OrderedSet<GraphInput<T>> = []
    var hashMap: [UInt: NodeId] = [:]
    var pendingMerges: [PendingMerge] = []
    var merges: [Merge: NodeId] = [:]
    var roots: [NodeId] = []
    var rootId: NodeId? = nil
}

// MARK: - Graph Element Helpers

extension Graph {
    func get(node id: NodeId) -> Node? {
        return nodes[Int(id)]
    }

    func get(input id: EndsId) -> GraphInput<T> {
        return inputs[Int(id)]
    }

    mutating func insertOrPush<I: IntoNode>(_ node: I, _ reserved: NodeId?) throws -> NodeId {
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

        for readyMerge in ready {
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
    mutating func push(input: GraphInput<T>) throws {
        if inputs.contains(input) {
            throw GraphError.DuplicatedInputs
        }

        let endId = inputs.reserve(input)
        let leafId = reserve(
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

                branchContent.merge(other: branch(from: child, childId), graph: &self)
            }

            let branchId = try reserve(
                branchContent,
                reserved
            )

            return branchId

        case .Literal(let str):
            // push a match into reserve or a new place
            return try reserve(Node.BranchContent(branches: [str: succ], miss: miss), reserved)
        case .Class(let classHIR):
            // push a class hir as usual
            return try push(classHIR, succ, miss, reserved)
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

        let lhs = get(node: a)
        let rhs = get(node: b)

        // work out pending merge and terminal conflicts
        switch (lhs, rhs) {
        case (nil, nil):
            // shouldn't happen
            throw GraphError.EmptyMerging
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
            throw GraphError.EmptyMerging
        }

        switch (lhs, rhs) {
        case (.Leaf, .Leaf):
            throw GraphError.MergingLeaves
        case _:
            break
        }

        var lhsContent = branch(from: lhs, a)
        let rhsContent = branch(from: rhs, b)

        lhsContent.merge(other: rhsContent, graph: &self)
        let into = try reserve(lhsContent, into)

        return into
    }

    mutating func makeRoot() throws -> NodeId {
        var rootId = reserve(Node.BranchContent())

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

        let rootIndex = Int(rootId)

        var marks = [Bool](repeating: false, count: nodes.count)
        marks[rootIndex] = true

        var rootNode = get(node: rootId)

        rootNode?.shake(marks: &marks, graph: &self)

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
