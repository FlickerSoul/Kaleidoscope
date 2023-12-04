//
//  TokenType.swift
//
//
//  Created by Larry Zeng on 11/26/23.
//

import Foundation
import KaleidoscopeLexer
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Callback Type

enum CallbackType {
    case Named(String)
    case Lambda(String)
    case Skip
}

enum TokenType {
    case callback(CallbackType)
    case standalone
}

public typealias CaseCallbackType<T: LexerProtocol> = (inout T) -> T where T.TokenType == T

// MARK: - Enum Case Token Registry

public struct EnumCaseRegistry: PeerMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
        return []
    }
}
