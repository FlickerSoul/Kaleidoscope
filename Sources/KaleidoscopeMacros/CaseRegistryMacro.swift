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

/// Types of callbacks, currently lambda is not usable due to swift compiler bug
enum CallbackType {
    /// A name reference of the callback
    case Named(String)
    /// A lambda expression
    case Lambda(String)
}

/// Types of tokens, based on how they are processed
enum TokenType {
    /// A token with a fill callback that transforms the token string slice into actual value
    case fillCallback(CallbackType)
    /// A token with a create callback that gives a into token type
    case createCallback(CallbackType)
    /// A token that does not carry any value
    case standalone
    /// A skip mark that signals the lexer to continue matching the next one
    case skip
}

// MARK: - Enum Case Token Registry

/// This macro is used for declaring tokens.
/// This peer macro is intended to be left blank and does not introduce any peers.
public struct EnumCaseRegistry: PeerMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
        return []
    }
}
