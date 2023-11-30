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
    case StartWithNonRoot
    case StartWithRoot
    case DuplicatedPath
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

enum NodeKind {
    case branch
    case data
    case end
    case miss
}

typealias NodeId = UInt
typealias InputId = UInt
typealias EndsId = InputId

public struct Node {
    let kind: NodeKind
    let data: Character?
    let then: NodeId
    let miss: NodeId
    let endInfo: InputId
}

// MARK: - Graph Input

public struct GraphInput<T> where T: Hashable {
    let token: T
    let hir: HIR
    let callback: MatchCallbackType
}

extension GraphInput: Hashable, Equatable {
    public static func == (lhs: GraphInput<T>, rhs: GraphInput<T>) -> Bool {
        return lhs.hir == rhs.hir && lhs.token == rhs.token
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hir)
        hasher.combine(token)
    }
}

// MARK: - Automata Graph

/// Automata representation graph
public struct Graph<T> where T: Hashable {
    var nodes: [Node?] = []
    var inputs: OrderedSet<GraphInput<T>> = []
    var roots: [NodeId] = []
}

// MARK: Handle ID Generation

extension Array where Element == Node? {
    var nextNodeId: NodeId {
        UInt(count)
    }

    mutating func reserve() -> NodeId {
        let id = nextNodeId
        append(nil)
        return id
    }
}

extension Graph {
    /// Get the next info ID, which is always
    /// equal to the length of the info list, or
    /// the index of next appended item
    var nextInputId: InputId {
        UInt(inputs.count)
    }

    /// Get the next end id, which is always
    /// equal to ``nextInfoId``
    var nextEndId: EndsId {
        UInt(inputs.count)
    }

    /// Get the next node id, which is alwayas
    /// euqal to the length of the node list, or
    /// the index of the next appended item
    var nextNodeId: NodeId {
        UInt(nodes.count)
    }
}

// MARK: Handle Graph Input

extension Graph {
    public mutating func pushInput(input: GraphInput<T>) throws {
        if inputs.contains(input) {
            throw GraphError.DuplicatedInputs
        }

        merge(input: input)

        inputs.append(input)
    }

    mutating func merge(input: GraphInput<T>) {}
}
