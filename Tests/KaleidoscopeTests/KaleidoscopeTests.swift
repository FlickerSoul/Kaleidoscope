import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(KaleidoscopeMacros)
import KaleidoscopeMacros

let testMacros: [String: Macro.Type] = [
    "caseGen": CaseGenerator.self,
]
#endif

final class kaleidoscopeTests: XCTestCase {
    func testMacro() throws {
        #if canImport(KaleidoscopeMacros)
        assertMacroExpansion(
            """
            enum Tokens {
                #caseGen("def")
            }
            """,
            expandedSource: """
            enum Tokens {
                case def
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
