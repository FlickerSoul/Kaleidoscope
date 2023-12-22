//
//  KaleidoscopeBuilder.swift
//
//
//  Created by Larry Zeng on 11/26/23.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

let KALEIDOSCOPE_PACKAGE_NAME: String = "Kaleidoscope"

let KALEIDOSCOPE_MACRO_NAME: String = "kaleidoscope"
let KALEIDOSCOPE_MACRO_SKIP_ATTR: String = "skip"

let KALEIDOSCOPE_REGEX_NAME: String = "regex"
let KALEIDOSCOPE_TOKEN_NAME: String = "token"

let KALEIDOSCOPE_PRIORITY_OPTION: String = "priority"
let KALEIDOSCOPE_ON_MATCH_OPTION: String = "onMatch"

/// This extension macro generates an extension to the decorated enum and make it conform to the lexer protocol
/// so that the decorated enum can be a tokenizer.
public struct KaleidoscopeBuilder: ExtensionMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw KaleidoscopeError.NotAnEnum
        }
        
        // get enum identity
        let enumIdent = enumDecl.name.text
        
        // generate graph
        var graph = Graph()
        
        // get the macro lists
        let kaleidoscopeMacroDelcList = enumDecl.attributes.filter { attr in
            let attrName: TypeSyntax? = attr.as(AttributeSyntax.self)?.attributeName
            let ident = attrName?.as(IdentifierTypeSyntax.self)?.name.text
            let member = attrName?.as(MemberTypeSyntax.self)
            let memberIdent = member?.name.text
            let memberType = member?.baseType.as(IdentifierTypeSyntax.self)?.name.text
            
            // check how many of the attributes are like
            // @kaleidoscope() or Kaleidoscope.kaleidoscope()
            return ident == KALEIDOSCOPE_MACRO_NAME || (memberIdent == KALEIDOSCOPE_MACRO_NAME && memberType == KALEIDOSCOPE_PACKAGE_NAME)
        }
        
        // if there are more than 1,
        // throw error to indicate duplication
        if kaleidoscopeMacroDelcList.count > 1 {
            throw KaleidoscopeError.MultipleMacroDecleration
        }
        
        if let kaleidoscopeAttrs = kaleidoscopeMacroDelcList[0].as(AttributeSyntax.self)?.arguments?.as(LabeledExprListSyntax.self) {
            for kaleidoscopeAttr in kaleidoscopeAttrs {
                switch kaleidoscopeAttr.label?.text {
                case KALEIDOSCOPE_MACRO_SKIP_ATTR:
                    guard let skipString = kaleidoscopeAttr.expression.as(StringLiteralExprSyntax.self)?.segments.description else {
                        throw KaleidoscopeError.ExpectingString
                    }
                    try graph.push(input: .init(token: "SKIP_REGEX_TOKEN", tokenType: .skip, hir: HIR(regex: skipString)))
                case _:
                    break
                }
            }
        }
        
        // get the member case xxx blocks
        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else {
                continue
            }
            
            // summarize `case  A, B, C(K.String), D(String, Int)`
            // get (name, paramTypes) tuples
            // for example, (A, nil), (C, ["K.String"])
            let caseTypes: [(name: String, paramTypes: [String]?)] = caseDecl.elements.map { element in
                (name: element.name.text, paramTypes: element.parameterClause?.parameters.map { $0.type.description })
            }
            
            var attrMatches: [AttrMatchInfo] = []
            
            // parse attributes
            for attr in caseDecl.attributes {
                guard let attr = attr.as(AttributeSyntax.self) else {
                    continue
                }
                
                let attrName: TypeSyntax? = attr.attributeName
                let ident = attrName?.as(IdentifierTypeSyntax.self)?.name.text
                let member = attrName?.as(MemberTypeSyntax.self)
                let memberIdent = member?.name.text
                let memberType = member?.baseType.as(IdentifierTypeSyntax.self)?.name.text
                
                switch (ident, memberIdent, memberType) {
                case (KALEIDOSCOPE_REGEX_NAME, _, _), (_, KALEIDOSCOPE_REGEX_NAME, KALEIDOSCOPE_PACKAGE_NAME):
                    try attrMatches.append(parse(regex: attr))
                case (KALEIDOSCOPE_TOKEN_NAME, _, _), (_, KALEIDOSCOPE_TOKEN_NAME, KALEIDOSCOPE_PACKAGE_NAME):
                    try attrMatches.append(parse(token: attr))
                case _:
                    break
                }
            }
            
            for token in caseTypes {
                for (hir, tokenType, priority) in attrMatches {
                    try graph.push(input: .init(token: token.name, tokenType: tokenType, hir: hir, priority: priority))
                }
            }
        }
        
        _ = try graph.makeRoot()
        let rootId = try graph.shake()
        
        var generator = Generator(graph: graph, enumIdent: enumIdent)
        
        let result: DeclSyntax = try """
        extension \(raw: enumIdent): LexerProtocol {
            typealias TokenType = Self
        
            public static func lex<RawSource>(_ lexer: inout LexerMachine<Self, RawSource>) throws {
                \(raw: generator.buildFunctions())
        
                try \(raw: generator.generateFuncIdent(nodeId: rootId))(&lexer)
            }
        
            public static func lexer<RawSource>(source: RawSource) -> LexerMachine<Self, RawSource> {
                return LexerMachine(source: source)
            }
        }
        """
        
        return [
            result.cast(ExtensionDeclSyntax.self)
        ]
    }
}

typealias AttrMatchInfo = (hir: HIR, type: TokenType, priority: UInt?)

extension SyntaxCollection {
    subscript(index: Int) -> Element {
        return self[self.index(startIndex, offsetBy: index)]
    }
}

func parse(regex: AttributeSyntax) throws -> AttrMatchInfo {
    return try parse(regex, isToken: false)
}

func parse(token: AttributeSyntax) throws -> AttrMatchInfo {
    return try parse(token, isToken: true)
}

/// Parses an enum case's information.
func parse(_ attr: AttributeSyntax, isToken: Bool) throws -> AttrMatchInfo {
    guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else {
        throw KaleidoscopeError.ParsingError
    }
    
    // TODO: this might be wrong
    guard let regexOrToken = arguments[0].expression.as(StringLiteralExprSyntax.self)?.segments.description else {
        throw KaleidoscopeError.ExpectingString
    }
    
    let hir: HIR
    if isToken {
        hir = try HIR(token: regexOrToken)
    } else {
        hir = try HIR(regex: regexOrToken)
    }
    
    var matchCallback: TokenType = .standalone
    var priority: UInt? = nil
    
    if let foundExpr = findExpression(KALEIDOSCOPE_ON_MATCH_OPTION, in: arguments)?.expression {
        if let lambda = foundExpr.as(ClosureExprSyntax.self) {
            // TODO: this might be wrong
            matchCallback = .callback(.Lambda(lambda.description))
        } else {
            // TODO: this might be wrong
            matchCallback = .callback(.Named(foundExpr.description))
        }
    }
    
    if let foundExpr = findExpression(KALEIDOSCOPE_PRIORITY_OPTION, in: arguments)?.expression {
        guard let num = foundExpr.as(IntegerLiteralExprSyntax.self) else {
            throw KaleidoscopeError.ExpectingIntegerLiteral
        }
        priority = UInt(num.literal.text)
    }
    
    return (hir, matchCallback, priority)
}

func findExpression(_ name: String, in exprList: LabeledExprListSyntax) -> LabeledExprSyntax? {
    for labeledExpr in exprList {
        if labeledExpr.label?.text == name {
            return labeledExpr
        }
    }
    
    return nil
}
