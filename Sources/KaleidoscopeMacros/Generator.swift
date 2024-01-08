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

extension DefaultStringInterpolation {
    mutating func appendInterpolation(indented string: String) {
        let indent = String(description.reversed().prefix { $0 == " " })
        if indent.isEmpty {
            appendInterpolation(string)
        } else {
            appendLiteral(string.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n" + indent))
        }
    }
}

/// Generates the lexer code
struct Generator {
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
            case .Seq(let content):
                body = buildSeq(node: content)
            case .none:
                throw GeneratorError.BuildingEmptyNode
            }

            let ident = generateFuncIdent(nodeId: nodeId)

            functionMapping[nodeId] = """
            func \(ident) (_ lexer: inout LexerMachine<Self>) throws {
                \(indented: body)
            }
            """
        }
    }

    public mutating func buildFunctions() throws -> String {
        try buildNodeFunctions()
        return functionMapping.values.joined(separator: "\n")
    }

    /// Generate leaf lexer handles, based on the token type
    /// - Parameters:
    ///     - node: the leaf graph node
    func buildLeaf(node: Node.LeafContent) -> String {
        let end = graph.inputs[node.endId]
        switch end.tokenType {
        case .skip:
            return "try lexer.skip()"
        case .standalone:
            return "try lexer.setToken(\(enumIdent).\(end.token))"
        case .fillCallback(let callbackDetail):
            switch callbackDetail {
            case .Named(let ident):
                return "try lexer.setToken(\(enumIdent).\(end.token)(\(ident)(&lexer)))"
            case .Lambda(let lambda):
                return "try lexer.setToken(\(enumIdent).\(end.token)(\(lambda)(&lexer)))"
            }
        case .createCallback(let callbackDetail):
            switch callbackDetail {
            case .Named(let ident):
                return "try lexer.setToken(\(ident)(&lexer))"
            case .Lambda(let lambda):
                return "try lexer.setToken(\(lambda)(&lexer))"
            }
        }
    }

    /// Generate branch lexer handles, where each branch corresponds to a swift case.
    /// Cases in the swift are grouped to reduce file length and complexity.
    /// - Parameters:
    ///     - node: the branch graph node
    func buildBranch(node: Node.BranchContent) -> String {
        var branches: [String] = []
        var mergeCaes: [NodeId: [Node.BranchHit]] = [:]
        for (hit, nodeId) in node.branches {
            if mergeCaes[nodeId] == nil {
                mergeCaes[nodeId] = []
            }

            mergeCaes[nodeId]!.append(hit)
        }

        for (nodeId, cases) in mergeCaes {
            let caseString = cases.map { $0.toCode() }.joined(separator: ", ")
            branches.append("""
            case \(caseString):
                try lexer.bump()
                try \(generateFuncIdent(nodeId: nodeId))(&lexer)
            """)
        }

        let miss: String
        if let missId = node.miss {
            miss = "try \(generateFuncIdent(nodeId: missId))(&lexer)"
        } else {
            miss = "try lexer.error()"
        }

        return """
        guard let scalar = lexer.peak() else {
            \(indented: miss)
            return
        }

        switch scalar {
            \(indented: branches.joined(separator: "\n"))

            case _:
            \(indented: miss)
        }
        """
    }

    func buildSeq(node: Node.SeqContent) -> String {
        let miss: String

        if let missId = node.miss?.miss {
            miss = "try \(generateFuncIdent(nodeId: missId))(&lexer)"
        } else {
            miss = "try lexer.error()"
        }

        return """
        guard let scalars = lexer.peak(for: \(node.seq.count)) else {
            \(indented: miss)
            return
        }

        if \(node.seq.toCode()) == scalars {
            try lexer.bump(by: \(node.seq.count))
            try \(generateFuncIdent(nodeId: node.then))(&lexer)
        } else {
            \(indented: miss)
        }
        """
    }

    /// Generate function identifier based for a graph node.
    /// - Parameters:
    ///   - nodeId: the ID of the node in the graph
    func generateFuncIdent(nodeId: UInt) -> String {
        generateFuncIdent(nodeId: Int(nodeId))
    }

    /// Generate function identifier given an integer, usually the node ID
    func generateFuncIdent(nodeId: Int) -> String {
        return "jumpTo_\(nodeId)"
    }
}
