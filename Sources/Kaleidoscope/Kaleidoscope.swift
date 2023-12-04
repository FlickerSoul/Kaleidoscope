// The Swift Programming Language
// https://docs.swift.org/swift-book

@_exported import KaleidoscopeLexer
import KaleidoscopeMacros
import SwiftSyntax

/// A macro that generates a enum case.
/// For example,
///
///     enum Tokens {
///         #caseGen("def")
///     }
///
/// will yield
///
///     enum Tokens {
///         case def
///     }
///
@freestanding(declaration, names: arbitrary)
public macro caseGen(_ value: String) = #externalMacro(module: "KaleidoscopeMacros", type: "CaseGenerator")

@attached(peer)
public macro token<T>(_ value: String, onMatch callback: ExactMatchCallbackType<T>? = nil, weight: UInt? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseTokenType")

@attached(peer)
public macro token(_ value: String, weight: UInt? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseTokenType")

@attached(peer)
public macro regex<T>(_ value: String, onMatch callback: ExactMatchCallbackType<T>? = nil, weight: UInt? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseTokenType")

@attached(peer)
public macro regex(_ value: String, weight: UInt? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseTokenType")

@attached(extension, conformances: LexerProtocol, names: arbitrary)
public macro kaleidoscope(skip chars: String? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "KaleidoscopeBuilder")
