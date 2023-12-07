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
enum PriorityTest {
    @token("fast")
    case Fast

    @token("fast", priority: 10)
    case Faaaast
}

let convertInt = { (lexer: inout LexerMachine<CallbackTest>) in Int(lexer.slice)! }

let convertDouble = { (lexer: inout LexerMachine<CallbackTest>) in Double(lexer.slice)! }

let toSubstring = { (lexer: inout LexerMachine<CallbackTest>) in lexer.slice }

@kaleidoscope(skip: " ")
enum CallbackTest {
    @regex("[0-9]*?.[0-9]+?", onMatch: convertDouble)
    case Double(Double)

    @regex("[0-9]+?", onMatch: convertInt)
    case Number(Int)

    @token("what", onMatch: toSubstring)
    case What(Substring)
}

final class TestTokenizer: XCTestCase {
    func testPriority() throws {
        _ = PriorityTest.lexer(source: "fast").toUnwrappedArray()
    }

    func testCallback() throws {
        _ = CallbackTest.lexer(source: "100 1.5 what").toUnwrappedArray()
    }
}
