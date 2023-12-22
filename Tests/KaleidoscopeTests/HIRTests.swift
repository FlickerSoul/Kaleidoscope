//
//  HIRTests.swift
//
//
//  Created by Larry Zeng on 11/30/23.
//

import XCTest

@testable import KaleidoscopeMacros

enum TestError: Error {
    case CannotGenerateCharacterSequence
}

func characters(_ start: Character, _ end: Character, inverted: Bool = false) -> HIR.ScalarByteRanges {
    return [start.scalarByte ... end.scalarByte]
}

func disemableString(_ string: String) -> HIR {
    return .Concat(string.map { .Literal($0.scalarBytes) })
}

func literal(_ char: Character) -> HIR {
    return .Literal(char.scalarBytes)
}

final class HIRTests: XCTestCase {
    func testHIRRegexGeneration() throws {
        let testCases: [(String, Result<HIR, HIRParsingError>)] = [
            (
                "ab",
                .success(disemableString("ab"))
            ),
            (
                " \n\t", .success(disemableString(" \n\t"))
            ),
            (
                "a*",
                .failure(HIRParsingError.GreedyMatchingMore)
            ),
            (
                "a|b",
                .success(.Alternation([literal("a"), literal("b")]))
            ),
            (
                "[a-z]",
                .success(.Class(characters("a", "z")))
            ),
            (
                "[a-c]+?",
                .success(.Concat([.Class(characters("a", "c")), .Loop(.Class(characters("a", "c")))]))
            ),
            (
                "[a-cx-z]+?",
                .success(.Concat([.Class(characters("a", "c") + characters("x", "z")), .Loop(.Class(characters("a", "c") + characters("x", "z")))]))
            ),

            (
                "(foo)+?",
                .success(.Concat([disemableString("foo"), .Loop(disemableString("foo"))]))
            ),
            (
                "(foo|bar)+?",
                .success(.Concat([.Alternation([disemableString("foo"), disemableString("bar")]), .Loop(.Alternation([disemableString("foo"), disemableString("bar")]))]))
            ),
            (
                ".",
                .success(.Class([HIR.ScalarByte.min ... HIR.ScalarByte.max]))
            ),
        ]

        for (regexContent, expected) in testCases {
            try XCTContext.runActivity(named: "Test regex `\(regexContent)`") { _ in
                switch expected {
                case .success(let result):
                    let actual = try HIR(regex: regexContent)
                    XCTAssertEqual(
                        actual,
                        result,
                        "Regex `\(regexContent)` HIR not correct"
                    )
                case .failure(let error):
                    XCTAssertThrowsError(try HIR(regex: regexContent)) { actual in
                        XCTAssertEqual(actual as! HIRParsingError, error, "Parsing `\(regexContent)`, expecting \(error), but got \(actual)")
                    }
                }
            }
        }
    }

    func testHIRTokenGeneration() throws {
        let tests: [(String, HIR)] = [
            ("\\w", disemableString("\\w")),
            ("\\[a-b\\]", disemableString("\\[a-b\\]")),
        ]

        for (tokenContent, expected) in tests {
            XCTContext.runActivity(named: "Test Token Generation `\(tokenContent)`") { _ in
                let actual = try! HIR(token: tokenContent)
                XCTAssertEqual(actual, expected, "The HIR generated for token `\(tokenContent)` is incorrect")
            }
        }
    }

    func testHIRPriority() throws {
        let tests: [(String, UInt)] = [
            ("ab", 4),
            ("[a-b]", 1),
            ("a|b", 2),
            ("(foo|bar)+?", 6),
            ("(foo|long)+?(bar)", 12),
        ]

        for (regexContent, expected) in tests {
            let hir = try! HIR(regex: regexContent)
            XCTContext.runActivity(named: "Test Priority of Regex `\(regexContent)`") { _ in
                let actual = hir.priority()
                XCTAssertEqual(actual, expected, "The priority should be \(expected) instead of \(actual)")
            }
        }
    }
}
