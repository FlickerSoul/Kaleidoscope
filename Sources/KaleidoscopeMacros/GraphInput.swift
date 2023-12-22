//
//  GraphInput.swift
//
//
//  Created by Larry Zeng on 12/22/23.
//

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
