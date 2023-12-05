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

func generateCharacters(_ start: Character, _ end: Character) throws -> [HIR] {
    guard let left = start.unicodeScalars.first?.value, let right = end.unicodeScalars.first?.value else {
        throw TestError.CannotGenerateCharacterSequence
    }
    return (left ... right).compactMap { guard let val = Unicode.Scalar($0) else { return nil }; return .Literal(val) }
}

func disemableString(_ string: String) -> HIR {
    return .Concat(string.unicodeScalars.map { .Literal($0) })
}

final class HIRTests: XCTestCase {
    func testHIRRegexGeneration() throws {
        let testCases: [(String, Result<HIR, HIRParsingError>)] = try [
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
                .success(.Alternation([.Literal("a"), .Literal("b")]))
            ),
            (
                "[a-z]",
                .success(.Class(.Alternation(generateCharacters("a", "z"))))
            ),
            (
                "[a-c]+?",
                .success(.Concat([.Class(.Alternation(generateCharacters("a", "c"))), .Loop(.Class(.Alternation(generateCharacters("a", "c"))))]))
            ),
            (
                "[a-cx-z]+?",
                .success(.Concat([.Class(.Alternation([.Alternation(generateCharacters("a", "c")), .Alternation(generateCharacters("x", "z"))])), .Loop(.Class(.Alternation([.Alternation(generateCharacters("a", "c")), .Alternation(generateCharacters("x", "z"))])))]))
            ),

            (
                "(foo)+?",
                .success(.Concat([disemableString("foo"), .Loop(disemableString("foo"))]))
            ),
            (
                "(foo|bar)+?",
                .success(.Concat([.Alternation([disemableString("foo"), disemableString("bar")]), .Loop(.Alternation([disemableString("foo"), disemableString("bar")]))]))
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
