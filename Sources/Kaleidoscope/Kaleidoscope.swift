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

@attached(peer)
public macro token<T, R>(_ value: String, weight: UInt? = nil, onMatch callback: CaseCallbackType<T, R>) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseRegistry")

@attached(peer)
public macro token(_ value: String, weight: UInt? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseRegistry")

@attached(peer)
public macro regex<T, R>(_ value: String, weight: UInt? = nil, onMatch callback: CaseCallbackType<T, R>) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseRegistry")

@attached(peer)
public macro regex(_ value: String, weight: UInt? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "EnumCaseRegistry")

@attached(extension, conformances: LexerProtocol, names: arbitrary)
public macro kaleidoscope(skip chars: String? = nil) = #externalMacro(module: "KaleidoscopeMacros", type: "KaleidoscopeBuilder")
