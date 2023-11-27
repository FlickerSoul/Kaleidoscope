import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct CaseGenerator: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let startIndex = node.argumentList.startIndex

        let caseNameExpr = node.argumentList[startIndex].expression.cast(StringLiteralExprSyntax.self)

        return ["case \(caseNameExpr.segments)"]
    }
}

@main
struct kaleidoscopePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CaseGenerator.self,
        EnumCaseTokenType.self
    ]
}
