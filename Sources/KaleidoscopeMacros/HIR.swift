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
    public typealias ScalarByte = UInt16
    public typealias ScalarBytes = [ScalarByte]

    public typealias Scalar = ClosedRange<ScalarByte>
    public typealias Scalars = [Scalar]

    static let SCALAR_RANGE = ScalarByte.min ... ScalarByte.max

    case Empty
    case Concat([HIR])
    case Alternation([HIR])
    case Loop(HIR)
    case Maybe(HIR)
    case Literal(Scalar)
    case Class([Scalar])
}

extension Unicode.Scalar {
    var scalarByte: HIR.ScalarByte {
        return HIR.ScalarBytes(self.utf16).first!
    }

    var scalar: HIR.Scalar {
        return self.scalarByte ... self.scalarByte
    }
}

extension Character {
    var scalarByte: HIR.ScalarByte {
        return HIR.ScalarBytes(self.utf16).first!
    }

    var scalar: HIR.Scalar {
        return self.scalarByte ... self.scalarByte
    }
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
    case QuoteInCharacterClass
    case WiderUnicodeThanSupported
}

// MARK: - Regex Repetition Kinds

/// A representation of regex repetition.
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
            self = try .Class(HIR.processCharacterClass(charClass))
        case .empty:
            self = .Empty
        case _:
            throw HIRParsingError.NotSupportedRegexNode
        }
    }

    internal init(_ quote: AST.Quote) {
        self = quote.literal.map { .Literal($0.scalar) }.wrapOrExtract(wrapper: HIR.Concat)
    }

    internal init(_ atom: AST.Atom) throws {
        switch atom.kind {
        case .char(let char), .keyboardMeta(let char), .keyboardControl(let char), .keyboardMetaControl(let char):
            self = .Literal(char.scalar)
        case .scalar(let scalar):
            self = .Literal(scalar.value.scalar)
        case .scalarSequence(let scalarSequence):
            self = scalarSequence.scalarValues.map { .Literal($0.scalar) }.wrapOrExtract(wrapper: HIR.Concat)
        case .escaped(let escaped):
            guard let scalar = escaped.scalarValue else {
                throw HIRParsingError.InvalidEscapeCharactor
            }
            self = .Literal(scalar.scalar)
        case .dot:
            self = .Literal(("." as Character).scalar)
        case .caretAnchor:
            self = .Literal(("^" as Character).scalar)
        case .dollarAnchor:
            self = .Literal(("$" as Character).scalar)
        case _:
            throw HIRParsingError.NotSupportedAtomKind
        }
    }

    internal static func parseRange(_ range: AST.CustomCharacterClass.Range) throws -> Scalars {
        let lhs = range.lhs.kind
        let rhs = range.rhs.kind
        if case .char(let leftChar) = lhs, case .char(let rightChar) = rhs {
            guard let start = leftChar.utf8.first, let end = rightChar.utf8.last else {
                throw HIRParsingError.IncorrectCharRange
            }
            return [ScalarByte(start) ... ScalarByte(end)]
        } else if case .scalar(let leftScalar) = lhs, case .scalar(let rightScalar) = rhs {
            guard let start = leftScalar.value.utf8.first, let end = rightScalar.value.utf8.last else {
                throw HIRParsingError.IncorrectCharRange
            }
            return [ScalarByte(start) ... ScalarByte(end)]
        } else {
            throw HIRParsingError.NotSupportedCharacterRangeKind
        }
    }

    internal static func processCharacterClass(_ charClass: AST.CustomCharacterClass) throws -> Scalars {
        let ranges: [Scalars] = try charClass.members.map { member in
            switch member {
            case .custom(let childMember):
                return try self.processCharacterClass(childMember).compactMap { $0 }
            case .range(let range):
                return try HIR.parseRange(range)
            case .atom(let atom):
                switch try HIR(atom) {
                case .Literal(let scalar):
                    return [scalar]
                case _:
                    throw HIRParsingError.NotSupportedAtomKind
                }
            case .quote:
                throw HIRParsingError.QuoteInCharacterClass
            case _:
                throw HIRParsingError.NotSupportedCharacterClass
            }
        }

        // sort out and make distinct ranges

        var flattened: Scalars = []

        for currRange in ranges.flatMap({ $0 }).sorted() {
            if flattened.count == 0 {
                flattened.append(currRange)
            } else {
                let prevResult = flattened[flattened.count - 1]
                if currRange.lowerBound <= prevResult.upperBound {
                    if currRange.upperBound <= prevResult.upperBound {
                        // perfectly contained in prev range,
                        continue
                    } else {
                        // has intersection
                        // ----
                        //  -----
                        flattened[flattened.count - 1] = prevResult.lowerBound ... currRange.upperBound
                    }
                } else {
                    // does not have intersection
                    // ---
                    //     ----
                    flattened.append(currRange)
                }
            }
        }

        // do invert
        if charClass.isInverted {
            var results: Scalars = []
            var remaining: Scalar? = Self.SCALAR_RANGE

            for scalar in flattened {
                guard let remainingUnwrapped = remaining else {
                    throw HIRParsingError.WiderUnicodeThanSupported
                }

                if remainingUnwrapped.lowerBound < scalar.lowerBound {
                    let left = remainingUnwrapped.lowerBound ... (scalar.lowerBound - 1)
                    results.append(left)
                } else if scalar.upperBound > remainingUnwrapped.upperBound {
                    throw HIRParsingError.WiderUnicodeThanSupported
                }

                if scalar.upperBound < remainingUnwrapped.upperBound {
                    remaining = scalar.upperBound + 1 ... remainingUnwrapped.upperBound
                } else {
                    remaining = nil
                }
            }

            if let remaining = remaining {
                results.append(remaining)
            }

            flattened = results
        }

        return flattened
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
    /// Calculate this hir's priority. It has the following property.
    /// The more specific, the higher the score is.
    /// The longer the regex is, the higher the score is.
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
