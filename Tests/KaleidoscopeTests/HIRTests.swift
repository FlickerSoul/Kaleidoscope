//
//  HIRTests.swift
//
//
//  Created by Larry Zeng on 11/30/23.
//

import XCTest

import KaleidoscopeMacros

enum TestError: Error {
    case CannotGenerateCharacterSequence
}

func generateCharacters(_ start: Character, _ end: Character) throws -> [HIR] {
    guard let left = start.unicodeScalars.first?.value, let right = end.unicodeScalars.first?.value else {
        throw TestError.CannotGenerateCharacterSequence
    }
    return (left ... right).compactMap { guard let val = UnicodeScalar($0) else { return nil }; return .Literal(string: String(Character(val))) }
}

func disemableString(_ string: String) -> HIR {
    return .Concat(string.map { .Literal(string: String($0)) })
}

final class HIRTests: XCTestCase {
    func testHIRGeneration() throws {
        let testCases: [(String, Result<HIR, HIRParsingError>)] = try [
            (
                "ab",
                .success(
                    .Concat(
                        [
                            .Literal(string: "a"),
                            .Literal(string: "b"),
                        ]
                    )
                )
            ),
            (
                "a*",
                .failure(HIRParsingError.GreedyMatchingMore)
            ),
            (
                "a|b",
                .success(.Alternation([.Literal(string: "a"), .Literal(string: "b")]))
            ),
            (
                "[a-z]",
                .success(.Alternation(generateCharacters("a", "z")))
            ),
            (
                "[a-c]+?",
                .success(.Concat([.Alternation(generateCharacters("a", "c")), .Loop(.Alternation(generateCharacters("a", "c")))]))
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
}
