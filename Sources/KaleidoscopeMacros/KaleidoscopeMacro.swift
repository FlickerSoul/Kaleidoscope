import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct kaleidoscopePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        EnumCaseRegistry.self,
        KaleidoscopeBuilder.self
    ]
}
