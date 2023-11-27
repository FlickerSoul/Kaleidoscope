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


public struct KaleidoscopeBuilder: MemberMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingMembersOf declaration: some SwiftSyntax.DeclGroupSyntax, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
        
        // check if there are multiple Kaleidoscoope Builder macros
        // raise error if that's the case
        
        // check if it's raw value styled enum
        // according to syntax
        // raw-value-style-enum-case → enum-case-name raw-value-assignment?
        // this is for call back type matching
        
        // loop through the cases collect tokens and their attributes
        
        // construct a grammar tree from tokens and
        // regex for fast matching
        
        // add members to enum
        // or alternatively, apply extensions to enum
        
        return []
    }
}
