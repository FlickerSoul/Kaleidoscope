//
//  TokenType.swift
//
//
//  Created by Larry Zeng on 11/26/23.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public struct EnumCaseTokenType: PeerMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
        return []
    }
}

