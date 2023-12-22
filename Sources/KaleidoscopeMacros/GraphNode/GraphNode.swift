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

/// Graph Node Type
public enum Node {
    /// The terminal of the graph
    case Leaf(Node.LeafContent)
    /// The state that can lead to multiple states
    case Branch(Node.BranchContent)
    /// A sequence of bytes
    case Seq(Node.SeqContent)
}

extension Node: IntoNode {
    public func into() -> Node {
        return self
    }
}
