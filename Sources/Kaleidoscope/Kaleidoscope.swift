// The Swift Programming Language
// https://docs.swift.org/swift-book

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
