//
//  BenchTest.swift
//
//
//  Created by Larry Zeng on 12/4/23.
//

import Kaleidoscope
import XCTest

@kaleidoscope(skip: "\t| |\n")
enum BenchTestToken {
    @regex(#"[a-zA-Z_$][a-zA-Z0-9_$]*?"#)
    case Identifier

    @regex(#""([^"\\]|\\t|\\n|\\n|\\")*?""#)
    case String

    @token(#"private"#)
    case Private

    @token(#"primitive"#)
    case Primitive

    @token(#"protected"#)
    case Protected

    @token(#"in"#)
    case In

    @token(#"instanceof"#)
    case Instanceof

    @token(#"."#)
    case Accessor

    @token(#"..."#)
    case Ellipsis

    @token(#"("#)
    case ParenOpen

    @token(#")"#)
    case ParenClose

    @token(#"{"#)
    case BraceOpen

    @token(#"}"#)
    case BraceClose

    @token(#"+"#)
    case OpAddition

    @token(#"++"#)
    case OpIncrement

    @token(#"="#)
    case OpAssign

    @token(#"=="#)
    case OpEquality

    @token(#"==="#)
    case OpStrictEquality

    @token(#"=>"#)
    case FatArrow
}

let SOURCE = """
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
foobar(protected primitive private instanceof in) { + ++ = == === => }
"""

let IDENTIFIERS = """
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton \
It was the year when they finally immanentized the Eschaton
"""

let STRINGS = #""tree" "to" "a" "graph" "that can" "more adequately represent" "loops and arbitrary state jumps" "with\"\"\"out" "the\n\n\n\n\n" "expl\"\"\"osive" "nature\"""of trying to build up all possible permutations in a tree." "tree" "to" "a" "graph" "that can" "more adequately represent" "loops and arbitrary state jumps" "with\"\"\"out" "the\n\n\n\n\n" "expl\"\"\"osive" "nature\"""of trying to build up all possible permutations in a tree." "tree" "to" "a" "graph" "that can" "more adequately represent" "loops and arbitrary state jumps" "with\"\"\"out" "the\n\n\n\n\n" "expl\"\"\"osive" "nature\"""of trying to build up all possible permutations in a tree." "tree" "to" "a" "graph" "that can" "more adequately represent" "loops and arbitrary state jumps" "with\"\"\"out" "the\n\n\n\n\n" "expl\"\"\"osive" "nature\"""of trying to build up all possible permutations in a tree.""#

let BENCH_SOURCE = [SOURCE, IDENTIFIERS, STRINGS]
let TOKEN_NUMs = [30 * 16, 13 * 10, 48]

final class TestBenchMark: XCTestCase {
    func testBenchCorrect() throws {
        for (index, (benchSource, tokenNum)) in zip(BENCH_SOURCE, TOKEN_NUMs).enumerated() {
            XCTContext.runActivity(named: "test parsing the \(index)th test with \(tokenNum) tokens") { _ in
                let tokens = Array(BenchTestToken.lexer(source: benchSource))

                _ = tokens.map { try! $0.get() }

                XCTAssertEqual(tokens.count, tokenNum, "token num of the \(index)th test did not match")
            }
        }
    }

    func testBenchSpeed() throws {
        let ITERATION_COUNT = 10

        for (index, (benchSource, tokenNum)) in zip(BENCH_SOURCE, TOKEN_NUMs).enumerated() {
            XCTContext.runActivity(named: "test parsing the \(index)th test with \(tokenNum) tokens") { _ in
                let startTime = Date()
                for _ in 0 ..< ITERATION_COUNT {
                    _ = Array(BenchTestToken.lexer(source: benchSource).map { $0.get })
                }
                let endTime = Date()

                let elapsedTime = endTime.timeIntervalSince(startTime)

                print("parsing \(benchSource.count) for \(ITERATION_COUNT) iterations in \(elapsedTime) seconds: \(Double(benchSource.unicodeScalars.count * ITERATION_COUNT) / Double(elapsedTime)) scalar/s")
            }
        }
    }
}
