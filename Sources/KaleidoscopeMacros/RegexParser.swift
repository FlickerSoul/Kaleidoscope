//
//  RegexParser.swift
//
//
//  Created by Larry Zeng on 11/27/23.
//

import _RegexParser
import Foundation

// MARK: - HIR and Errors

/// High-level Intermediate Representation
///
/// This is an abstraction to be fed into automata building,
/// and to determine the weight the expression.
/// The repetitions are unrolled to improve performance
///
/// - SeeAlso
/// [Regex AST API](https://swiftinit.org/docs/swift/_regexparser/ast)
/// - SeeAlso
/// [AST Node API](https://swiftinit.org/docs/swift/_regexparser/ast/node)
public indirect enum HIR: Hashable {
    case Empty
    case Concat([HIR])
    case Alternation([HIR])
    case Loop(HIR)
    case Maybe(HIR)
    case Literal(Unicode.Scalar)
    case Class(HIR)
}

public enum HIRParsingError: Error {
    case InvalidRepetitionRange
    case GreedyMatchingMore
    case NotSupportedRepetitionKind
    case NotSupportedQualification
    case NotSupportedAtomKind
    case NotSupportedRegexNode
    case NotSupportedCharacterClass
    case IncorrectCharRange
    case IncorrectChar
    case NotSupportedCharacterRangeKind
    case InvalidEscapeCharactor
}

// MARK: - Regex Repetition Kinds

enum RepetitionRange {
    case exactly(right: Int)
    case nOrMore(left: Int)
    case upToN(right: Int)
    case range(left: Int, right: Int)

    init(_ amount: AST.Quantification.Amount) throws {
        var left, right: AST.Atom.Number?

        switch amount {
        case .exactly(right):
            break
        case .nOrMore(left):
            break
        case .upToN(right):
            break
        case .range(left, right):
            break
        case _:
            break
        }

        let left_num = left?.value ?? -1
        let right_num = right?.value ?? -1

        switch amount {
        case .exactly:
            self = .exactly(right: right_num)
        case .nOrMore:
            self = .nOrMore(left: right_num)
        case .oneOrMore:
            self = .nOrMore(left: 1)
        case .zeroOrMore:
            self = .nOrMore(left: 0)
        case .upToN:
            self = .upToN(right: right_num)
        case .range:
            self = .range(left: left_num, right: right_num)
        case .zeroOrOne:
            self = .range(left: 0, right: 1)
        case _:
            throw HIRParsingError.InvalidRepetitionRange
        }
    }
}

// MARK: - Flat HIR Array

extension Array where Element == HIR {
    func wrapOrExtract(wrapper: ([HIR]) -> HIR) -> HIR {
        if self.count == 1 {
            return self[0]
        } else {
            return wrapper(self)
        }
    }
}

// MARK: - Init

public extension HIR {
    init(regex string: String, option: SyntaxOptions = .traditional) throws {
        self = try HIR(ast: parse(string, option))
    }

    init(token string: String) throws {
        self = try HIR(regex: NSRegularExpression.escapedPattern(for: string))
    }

    init(ast: AST) throws {
        self = try HIR(node: ast.root)
    }

    init(node: AST.Node) throws {
        switch node {
        case .alternation(let alter):
            let children = try alter.children.map { try HIR(node: $0) }.compactMap { $0 }
            self = children.wrapOrExtract(wrapper: HIR.Alternation)
        case .concatenation(let concat):
            let children = try concat.children.map { try HIR(node: $0) }.compactMap { $0 }
            self = children.wrapOrExtract(wrapper: HIR.Concat)
        case .group(let group):
            self = try HIR(node: group.child)
        case .quantification(let qualification):
            switch qualification.amount.value {
            case .zeroOrMore where qualification.kind.value == .eager, .oneOrMore where qualification.kind.value == .eager:
                throw HIRParsingError.GreedyMatchingMore
            case _:
                let child = try HIR(node: qualification.child)

                switch qualification.amount.value {
                case .zeroOrMore, .oneOrMore:
                    switch qualification.kind.value {
                    case .reluctant, .possessive:
                        let range = try RepetitionRange(qualification.amount.value)
                        self = HIR.processRange(child: child, kind: range)
                    case _:
                        throw HIRParsingError.NotSupportedRepetitionKind
                    }
                case .zeroOrOne, .exactly, .nOrMore, .upToN, .range:
                    let range = try RepetitionRange(qualification.amount.value)
                    self = HIR.processRange(child: child, kind: range)
                case _:
                    throw HIRParsingError.NotSupportedQualification
                }
            }
        case .quote(let quote):
            self = HIR(quote)
        case .atom(let atom):
            self = try HIR(atom)
        case .customCharacterClass(let charClass):
            self = try HIR.processCharacterClass(charClass)
        case .empty:
            self = .Empty
        case _:
            throw HIRParsingError.NotSupportedRegexNode
        }
    }

    internal init(_ quote: AST.Quote) {
        self = .Concat(quote.literal.unicodeScalars.map { .Literal($0) })
    }

    internal init(_ atom: AST.Atom) throws {
        switch atom.kind {
        case .char(let char):
            self = .Concat(char.unicodeScalars.map { .Literal($0) })
        case .scalar(let scalar):
            self = .Literal(scalar.value)
        case .scalarSequence(let scalarSequence):
            self = .Concat(scalarSequence.scalarValues.map { .Literal($0) })
        case .escaped(let escaped):
            guard let scalar = escaped.scalarValue else {
                throw HIRParsingError.InvalidEscapeCharactor
            }
            self = .Literal(scalar)
        case .dot:
            self = .Literal(".")
        case .caretAnchor:
            self = .Literal("^")
        case .dollarAnchor:
            self = .Literal("$")
        case _:
            throw HIRParsingError.NotSupportedAtomKind
        }
    }

    internal init(_ range: AST.CustomCharacterClass.Range) throws {
        let lhs = range.lhs.kind
        let rhs = range.rhs.kind
        if case .char(let leftChar) = lhs, case .char(let rightChar) = rhs {
            guard let start = leftChar.unicodeScalars.first?.value, let end = rightChar.unicodeScalars.first?.value else {
                throw HIRParsingError.IncorrectCharRange
            }
            self = try .Alternation(
                (start ... end).map {
                    guard let unicode = Unicode.Scalar($0) else {
                        throw HIRParsingError.IncorrectChar
                    }
                    return .Literal(unicode)
                }
            )
        } else if case .scalar(let leftScalar) = lhs, case .scalar(let rightScalar) = rhs {
            self = try .Alternation(
                (leftScalar.value.value ... rightScalar.value.value).map {
                    guard let unicode = Unicode.Scalar($0) else {
                        throw HIRParsingError.IncorrectChar
                    }
                    return .Literal(unicode)
                }
            )
        } else {
            throw HIRParsingError.NotSupportedCharacterRangeKind
        }
    }

    internal static func processCharacterClass(_ charClass: AST.CustomCharacterClass) throws -> HIR {
        let members = try charClass.members.map { member in
            switch member {
            case .custom(let childMember):
                return try self.processCharacterClass(childMember)
            case .range(let range):
                return try HIR(range)
            case .atom(let atom):
                return try HIR(atom)
            case .quote(let quote):
                return HIR(quote)
            case _:
                throw HIRParsingError.NotSupportedCharacterClass
            }
        }

        return .Class(members.wrapOrExtract(wrapper: HIR.Alternation))
    }

    internal static func processRange(child: HIR, kind: RepetitionRange) -> HIR {
        var children: [HIR]
        switch kind {
        case .exactly(let right):
            children = (0 ..< right).map { _ in child }
        case .nOrMore(let left):
            children = (0 ..< left).map { _ in child }
            children.append(.Loop(child))
        case .upToN(let right):
            children = (0 ..< right).map { _ in .Maybe(child) }
        case .range(let left, let right):
            children = (0 ..< left).map { _ in child }
            children.append(contentsOf: (left ..< right).map { _ in .Maybe(child) })
        }

        return children.wrapOrExtract(wrapper: HIR.Concat)
    }
}

// MARK: - HIR priority

public extension HIR {
    func priority() -> UInt {
        switch self {
        case .Empty, .Loop, .Maybe:
            return 0
        case .Class:
            return 1
        case .Literal:
            return 2
        case .Concat(let children):
            return children.map { $0.priority() }.reduce(0, +)
        case .Alternation(let children):
            if children.count > 0 {
                let priorities = children.map { $0.priority() }
                return priorities.reduce(priorities[0], min)
            } else {
                return 0
            }
        }
    }
}
