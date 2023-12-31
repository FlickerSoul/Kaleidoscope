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
    public typealias ScalarByte = UInt32
    public typealias ScalarBytes = [ScalarByte]

    public typealias ScalarByteRange = ClosedRange<ScalarByte>
    public typealias ScalarByteRanges = [ScalarByteRange]

    static let SCALAR_RANGE = ScalarByte.min ... ScalarByte.max

    case Empty
    case Concat([HIR])
    case Alternation([HIR])
    case Loop(HIR)
    case Maybe(HIR)
    case Literal(ScalarBytes)
    case Class([ScalarByteRange])
}

extension Unicode.Scalar {
    var scalarByte: HIR.ScalarByte {
        return self.value
    }

    var scalarBytes: HIR.ScalarBytes {
        return [self.value]
    }
}

extension Character {
    var scalarByte: HIR.ScalarByte {
        return self.unicodeScalars.first!.scalarByte
    }

    var scalarBytes: HIR.ScalarBytes {
        return [self.scalarByte]
    }
}

extension HIR.ScalarByteRange: @retroactive Comparable {
    public static func < (lhs: ClosedRange<Bound>, rhs: ClosedRange<Bound>) -> Bool {
        return lhs.lowerBound < rhs.lowerBound || (lhs.lowerBound == rhs.lowerBound && lhs.upperBound < rhs.upperBound)
    }

    public func toCode() -> String {
        if lowerBound == upperBound {
            return "\(lowerBound)"
        } else {
            return "\(lowerBound) ... \(upperBound)"
        }
    }
}

public extension HIR.ScalarBytes {
    func toCode() -> String {
        return self.description
    }
}

extension HIR.ScalarByte {
    var scalarByteRange: HIR.ScalarByteRange {
        return self ... self
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
        self = quote.literal.map { .Literal($0.scalarBytes) }.wrapOrExtract(wrapper: HIR.Concat)
    }

    internal init(_ atom: AST.Atom) throws {
        switch atom.kind {
        case .char(let char), .keyboardMeta(let char), .keyboardControl(let char), .keyboardMetaControl(let char):
            self = .Literal(char.scalarBytes)
        case .scalar(let scalar):
            self = .Literal(scalar.value.scalarBytes)
        case .scalarSequence(let scalarSequence):
            self = scalarSequence.scalarValues.map { .Literal($0.scalarBytes) }.wrapOrExtract(wrapper: HIR.Concat)
        case .escaped(let escaped):
            guard let scalar = escaped.scalarValue else {
                throw HIRParsingError.InvalidEscapeCharactor
            }
            self = .Literal(scalar.scalarBytes)
        case .dot:
            // wildcard
            self = .Class([HIR.SCALAR_RANGE])
        case .caretAnchor, .dollarAnchor, _:
            // start of the line
            // end of the line
            // and other things
            throw HIRParsingError.NotSupportedAtomKind
        }
    }

    internal static func parseRange(_ range: AST.CustomCharacterClass.Range) throws -> ScalarByteRanges {
        let lhs = range.lhs.kind
        let rhs = range.rhs.kind
        if case .char(let leftChar) = lhs, case .char(let rightChar) = rhs {
            let start = leftChar.scalarByte
            let end = rightChar.scalarByte

            return [start ... end]
        } else if case .scalar(let leftScalar) = lhs, case .scalar(let rightScalar) = rhs {
            let start = leftScalar.value.scalarByte
            let end = rightScalar.value.scalarByte
            return [start ... end]
        } else {
            throw HIRParsingError.NotSupportedCharacterRangeKind
        }
    }

    internal static func processCharacterClass(_ charClass: AST.CustomCharacterClass) throws -> ScalarByteRanges {
        let ranges: [ScalarByteRanges] = try charClass.members.map { member in
            switch member {
            case .custom(let childMember):
                return try self.processCharacterClass(childMember).compactMap { $0 }
            case .range(let range):
                return try HIR.parseRange(range)
            case .atom(let atom):
                switch try HIR(atom) {
                case .Literal(let scalar):
                    assert(scalar.count == 1)

                    return [scalar[0] ... scalar[0]]
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
        var flattened: ScalarByteRanges = []

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
            var results: ScalarByteRanges = []
            var remaining: ScalarByteRange? = Self.SCALAR_RANGE

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
