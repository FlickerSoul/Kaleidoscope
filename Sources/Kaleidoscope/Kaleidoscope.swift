// The Swift Programming Language
// https://docs.swift.org/swift-book

@_exported import KaleidoscopeLexer
import SwiftSyntax

// MARK: - callback type

/// Token callback type.
public typealias CaseCallbackType<T: LexerProtocol, R> = (inout LexerMachine<T>) -> R

// MARK: - Enum Case Decorators

/// Token definition macro, with a callback
@attached(peer)
public macro token<T: LexerProtocol, R>(_ value: String, priority: UInt? = nil, onMatch callback: @escaping CaseCallbackType<T, R>) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseRegistry")

/// Token definition macro, without a callback
@attached(peer)
public macro token(_ value: String, priority: UInt? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseRegistry")

/// Token regex definition macro, with a callback
@attached(peer)
public macro regex<T: LexerProtocol, R>(_ value: String, priority: UInt? = nil, onMatch callback: @escaping CaseCallbackType<T, R>) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseRegistry")

/// Token regex definition macro, without a callback
@attached(peer)
public macro regex(_ value: String, priority: UInt? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseRegistry")

// MARK: - Enum Builder

/// Lexer Conformance Macro
@attached(extension, conformances: LexerProtocol, names: arbitrary)
public macro kaleidoscope(skip chars: String? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "KaleidoscopeBuilder")
