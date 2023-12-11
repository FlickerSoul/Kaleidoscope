//
//  AutomataBuilderTests.swift
//
//
//  Created by Larry Zeng on 12/2/23.
//

@testable import KaleidoscopeMacros
import XCTest

func branch(_ children: [Character: NodeId], _ miss: NodeId? = nil, inverted: Bool = false) -> Node {
    return .Branch(.init(branches: Dictionary(uniqueKeysWithValues: children.map { ($0.scalar, $1) }), miss: miss))
}

func branch(_ children: [Node.BranchHit: NodeId], _ miss: NodeId? = nil, inverted: Bool = false) -> Node {
    return .Branch(.init(branches: children, miss: miss))
}

func range(_ lhs: Character, _ rhs: Character) -> Node.BranchHit {
    return lhs.scalarByte...rhs.scalarByte
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
                nodes: [branch([range("a", "b"): 3], 5), branch(["a": 3, "b": 0], 4), branch(["a": 1, "b": 3]), branch([range("a", "b"): 3], 4), leaf(1), leaf(0)],
                root: 2
            ),
            (
                regexs: ["ab", "[^a]"],
                nodes: [branch([range("a", "a"): 2, range("b", Character(Unicode.Scalar(HIR.ScalarByte.max)!)): 1, range(Character(Unicode.Scalar(0)), "`"): 1]), leaf(1), branch(["b": 3]), leaf(0)],
                root: 0
            ),
            (
                regexs: ["ab", "[^bc]+?"],
                nodes: [branch([0...97: 2, 98...98: 4, 100...65535: 2], 3), branch([97...97: 0, 100...65535: 2, 0...96: 2]), branch([0...97: 2, 100...65535: 2], 3), leaf(1), leaf(0)],
                root: 1
            )
        ]

        for (regexContents, expectedNodes, root) in tests {
            try XCTContext.runActivity(named: "Test `\(regexContents) graph generation`") { _ in
                var graph = Graph()
                for regexContent in regexContents {
                    let hir = try HIR(regex: regexContent)
                    try graph.push(input: .init(token: "LEAF", tokenType: .standalone, hir: hir))
                }

                _ = try graph.makeRoot()
                _ = try graph.shake()

                XCTAssertEqual(graph.nodes, expectedNodes, "\(regexContents) graph comp failed")
                XCTAssertEqual(graph.rootId, .some(root), "\(regexContents) graph root comp failed")
            }
        }
    }
}
