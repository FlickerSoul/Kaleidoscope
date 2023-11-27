import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(KaleidoscopeMacros)
import KaleidoscopeMacros

let enumCaseMacros: [String: Macro.Type] = [
    "caseGen": CaseGenerator.self,
    "token": EnumCaseTokenType.self,
    "regex": EnumCaseTokenType.self,
]
#endif

final class kaleidoscopeTests: XCTestCase {
    func testCaseGeneration() throws {
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
            macros: enumCaseMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testCaseTokenAttribute() throws {
        #if canImport(KaleidoscopeMacros)
        assertMacroExpansion(
            """
            enum Tokens {
                @token("def")
                case def
            }
            """,
            expandedSource: """
            enum Tokens {
                case def
            }
            """,
            macros: enumCaseMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
