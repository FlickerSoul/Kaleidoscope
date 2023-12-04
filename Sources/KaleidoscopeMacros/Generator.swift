//
//  Generator.swift
//
//
//  Created by Larry Zeng on 12/4/23.
//

import SwiftSyntax

// MARK: - Generator

enum GeneratorError: Error {
    case BuildingEmptyNode
}

struct Generator {
    /// Generate function definitions
    let graph: Graph
    let enumIdent: String
    var functionMapping: [Int: String] = [:]

    mutating func buildNodeFunctions() throws {
        for (nodeId, node) in graph.nodes.enumerated() {
            let body: String
            switch node {
            case .Leaf(let content):
                body = buildLeaf(node: content)
            case .Branch(let content):
                body = buildBranch(node: content)
            case .none:
                throw GeneratorError.BuildingEmptyNode
            }

            let ident = generateFuncIdent(nodeId: nodeId)

            functionMapping[nodeId] = """
            func \(ident) (_ lexer: inout LexerMachine<Self>) throws {
                \(body)
            }
            """
        }
    }

    public mutating func buildFunctions() throws -> String {
        try buildNodeFunctions()
        return functionMapping.values.joined(separator: "\n")
    }

    func buildLeaf(node: Node.LeafContent) -> String {
        let end = graph.inputs[node.endId]
        switch end.tokenType {
        case .standalone:
            return """
            try lexer.setToken(\(enumIdent).\(end.token))
            """
        case .callback(let callbackDetail):
            switch callbackDetail {
            case .Skip:
                return """
                lexer.reset()
                \(enumIdent).lex(&lexer)
                """
            case .Named(let ident):
                return """
                try lexer.setToken(\(enumIdent).\(end.token)(\(ident)(&lexer)))
                """
            case .Lambda(let lambda):
                return """
                try lexer.setToken(\(enumIdent),\(end.token))(\(lambda)(&lexer))
                """
                // TODO: the lambda to string might not work?
            }
        }
    }

    func buildBranch(node: Node.BranchContent) -> String {
        var branches: [String] = []
        for (hit, nodeId) in node.branches {
            branches.append("""
            case "\(hit)":
                try lexer.bump()
                try \(generateFuncIdent(nodeId: nodeId))(&lexer)
            """)
        }

        let miss: String
        if let missId = node.miss {
            miss = """
            case _:
                try \(generateFuncIdent(nodeId: missId))(&lexer)
            """
        } else {
            miss = """
            case _:
                lexer.error()
            """
        }

        return """
        switch lexer.peak() {
            \(branches.joined(separator: "\n"))
            \(miss)
        }
        """
    }

    func generateFuncIdent(nodeId: UInt) -> String {
        generateFuncIdent(nodeId: Int(nodeId))
    }

    func generateFuncIdent(nodeId: Int) -> String {
        return "jumpTo_\(nodeId)"
    }
}
