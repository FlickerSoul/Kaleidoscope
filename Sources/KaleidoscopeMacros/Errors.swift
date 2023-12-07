//
//  Errors.swift
//
//
//  Created by Larry Zeng on 11/25/23.
//

import Foundation

enum KaleidoscopeError: Error {
    case SyntaxError
    case NotAnEnum
    case MultipleMacroDecleration
    case ParsingError
    case ExpectingString
    case ExpectingIntegerLiteral
}
