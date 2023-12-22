//
//  TokenizerTests.swift
//
//
//  Created by Larry Zeng on 12/7/23.
//

import Kaleidoscope
import KaleidoscopeMacros
import XCTest

@kaleidoscope()
enum PriorityTest: Equatable {
    @token("fast")
    case Fast

    @token("fast", priority: 10)
    case Faaaast
}

let convertInt = { (lexer: inout LexerMachine<CallbackTest>) in Int(lexer.rawSlice)! }

let convertDouble = { (lexer: inout LexerMachine<CallbackTest>) in Double(lexer.rawSlice)! }

let toSubstring = { (lexer: inout LexerMachine<CallbackTest>) in lexer.rawSlice }

@kaleidoscope(skip: " ")
enum CallbackTest: Equatable {
    @regex(#"[0-9]*?\.[0-9]+?"#, onMatch: convertDouble)
    case Double(Double)

    @regex("[0-9]+?", onMatch: convertInt)
    case Number(Int)

    @token("what", onMatch: toSubstring)
    case What(Substring)

    @regex("//.*?", onMatch: toSubstring)
    case Comment(Substring)
}

final class TestTokenizer: XCTestCase {
    func testPriority() throws {
        XCTAssertEqual(PriorityTest.lexer(source: "fast").toUnwrappedArray(), [PriorityTest.Faaaast])
    }

    func testCallback() throws {
        XCTAssertEqual(CallbackTest.lexer(source: "100 1.5 what // this is a comment").toUnwrappedArray(), [CallbackTest.Number(100), CallbackTest.Double(1.5), CallbackTest.What("what"), CallbackTest.Comment("// this is a comment")])
    }
}
