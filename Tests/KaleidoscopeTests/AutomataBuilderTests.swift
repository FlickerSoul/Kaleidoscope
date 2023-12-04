//
//  AutomataBuilderTests.swift
//
//
//  Created by Larry Zeng on 12/2/23.
//

import _RegexParser
@testable import KaleidoscopeMacros
import XCTest

enum Token: Hashable {
    case first
    case second
}

func branch(_ children: [Character: NodeId], _ miss: NodeId? = nil) -> Node {
    return .Branch(.init(branches: children, miss: miss))
}

func leaf(_ end: EndsId) -> Node {
    return .Leaf(.init(endId: end))
}

final class GraphTests: XCTestCase {
    func testBuildGraph() throws {
        let tests: [(regexs: [String], nodes: [Node?], root: NodeId)] = [
            (
                regexs: ["ab"],
                nodes: [branch(["a": 1]), branch(["b": 2]), leaf(0)],
                root: 0
            ),
            (
                regexs: ["ab", "ab(b)+?"],
                nodes: [branch(["b": 3], 5), branch(["b": 0]), branch(["a": 1]), branch(["b": 3], 4), leaf(1), leaf(0)],
                root: 2
            ),
            (
                regexs: ["ab", "[a-b]+?"],
                nodes: [branch(["b": 3, "a": 3], 5), branch(["a": 3, "b": 0], 4), branch(["a": 1, "b": 3]), branch(["a": 3, "b": 3], 4), leaf(1), leaf(0)],
                root: 2
            )
        ]

        for (regexContents, expectedNodes, root) in tests {
            try XCTContext.runActivity(named: "Test `\(regexContents) graph generation`") { _ in
                var graph = Graph<Token>()
                for regexContent in regexContents {
                    let hir = try HIR(regex: regexContent)
                    try graph.push(input: .init(token: .first, hir: hir))
                }

                _ = try graph.makeRoot()
                _ = try graph.shake()

                XCTAssertEqual(graph.nodes, expectedNodes)
                XCTAssertEqual(graph.rootId, .some(root))
            }
        }
    }
}
