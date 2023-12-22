//
//  Lexer.swift
//
//
//  Created by Larry Zeng on 12/4/23.
//

public enum LexerError: Error {
    case SourceBoundExceeded
    case EmptyToken
    case DuplicatedToken
    case NotMatch
}

public protocol Into<IntoType> {
    associatedtype IntoType

    func into() -> IntoType
}

public protocol LexerProtocol {
    associatedtype TokenType: LexerProtocol
    typealias Source = [UInt32]
    typealias Slice = Source.SubSequence
    typealias TokenStream = [TokenType]

    static func lex<RawSource>(_ lexer: inout LexerMachine<Self, RawSource>) throws
    static func lexer<RawSource>(source: any Into<Source>) -> LexerMachine<Self, RawSource>
}

public enum TokenResult<Token: LexerProtocol>: Equatable, Into {
    public typealias IntoType = Self

    case result(Token)
    case skipped

    public static func == (lhs: TokenResult, rhs: TokenResult) -> Bool {
        switch (lhs, rhs) {
        case (.skipped, skipped):
            return true
        case _:
            return false
        }
    }

    public static func == (lhs: TokenResult, rhs: TokenResult) -> Bool where Token: Equatable {
        switch (lhs, rhs) {
        case (.skipped, .skipped):
            return true
        case (.result(let lhs), .result(let rhs)):
            return lhs == rhs
        case _:
            return false
        }
    }

    public func into() -> TokenResult<Token> {
        return self
    }
}

public struct LexerMachine<Token: LexerProtocol, RawSource: Into<Token.Source> & BidirectionalCollection> {
    public typealias RawSlice = RawSource.SubSequence

    let rawSource: RawSource
    let source: Token.Source
    var token: TokenResult<Token>?
    var tokenStart: Int
    var tokenEnd: Int
    var failed: Bool

    public init(source: RawSource, token: TokenResult<Token>? = nil, tokenStart: Int = 0, tokenEnd: Int = 0) {
        self.rawSource = source
        self.source = rawSource.into()
        self.token = token
        self.tokenStart = tokenStart
        self.tokenEnd = tokenEnd
        self.failed = false
    }

    @inline(__always)
    public var boundary: Int {
        return source.count
    }

    @inline(__always)
    public var span: Range<Int> {
        return tokenStart ..< tokenEnd
    }

    @inline(__always)
    public var rawSlice: RawSlice {
        let start = rawSource.startIndex
        let range = rawSource.index(start, offsetBy: tokenStart) ..< rawSource.index(start, offsetBy: tokenEnd)
        return rawSource[range]
    }

    @inline(__always)
    public var rawRemainder: RawSlice {
        let start = rawSource.startIndex
        let range = rawSource.index(start, offsetBy: tokenEnd) ..< rawSource.index(start, offsetBy: boundary)

        return rawSource[range]
    }

    @inline(__always)
    public mutating func bump(by: Int) throws {
        tokenEnd += by
        if tokenEnd > boundary {
            throw LexerError.SourceBoundExceeded
        }
    }

    @inline(__always)
    public mutating func bump() throws {
        try bump(by: 1)
    }

    @inline(__always)
    public mutating func reset() {
        tokenStart = tokenEnd
    }

    @inline(__always)
    mutating func take() throws -> TokenResult<Token> {
        switch token {
        case .none:
            throw LexerError.EmptyToken
        case .some(let result):
            token = nil
            return result
        }
    }

    @inline(__always)
    public var spanned: SpannedLexerIter<Token, RawSource> {
        return .init(lexer: self)
    }

    @inline(__always)
    public var sliced: SlicedLexerIter<Token, RawSource> {
        return .init(lexer: self)
    }

    @inline(__always)
    public var spannedAndSliced: SpannedSlicedLexerIter<Token, RawSource> {
        return .init(lexer: self)
    }

    @inline(__always)
    public mutating func setToken(_ token: Token) throws {
        guard self.token == nil || self.token == .skipped else {
            throw LexerError.DuplicatedToken
        }
        self.token = .result(token)
    }

    @inline(__always)
    public mutating func error() throws {
        throw LexerError.NotMatch
    }

    @inline(__always)
    public mutating func skip() throws {
        if tokenStart == tokenEnd {
            tokenEnd = tokenEnd + 1
            tokenStart = tokenEnd
        } else {
            reset()
        }

        token = .skipped

        if tokenEnd < boundary {
            try Token.lex(&self)
        }
    }

    public func toArray() -> [Result<Token, Error>] {
        return Array(self)
    }

    public func toUnwrappedArray() -> [Token] {
        return Array(self).map { try! $0.get() }
    }
}

extension LexerMachine: Sequence, IteratorProtocol {
    public mutating func next() -> Result<Token, Error>? {
        tokenStart = tokenEnd

        if tokenEnd == boundary || failed {
            return nil
        }

        do {
            try Token.lex(&self)
            switch try take() {
            case .result(let token):
                return .success(token)
            case .skipped:
                return nil
            }
        } catch {
            failed = true
            return .failure(error)
        }
    }
}

public struct SpannedLexerIter<Token: LexerProtocol, RawSource: Into<Token.Source> & BidirectionalCollection>: Sequence, IteratorProtocol {
    var lexer: LexerMachine<Token, RawSource>

    public mutating func next() -> (Result<Token, Error>, Range<Int>)? {
        if let token = lexer.next() {
            return (token, lexer.span)
        } else {
            return nil
        }
    }
}

public struct SlicedLexerIter<Token: LexerProtocol, RawSource: Into<Token.Source> & BidirectionalCollection>: Sequence, IteratorProtocol {
    var lexer: LexerMachine<Token, RawSource>

    public mutating func next() -> (Result<Token, Error>, RawSource.SubSequence)? {
        if let token = lexer.next() {
            return (token, lexer.rawSlice)
        } else {
            return nil
        }
    }
}

public struct SpannedSlicedLexerIter<Token: LexerProtocol, RawSource: Into<Token.Source> & BidirectionalCollection>: Sequence, IteratorProtocol {
    var lexer: LexerMachine<Token, RawSource>

    public mutating func next() -> (Result<Token, Error>, Range<Int>, RawSource.SubSequence)? {
        if let token = lexer.next() {
            return (token, lexer.span, lexer.rawSlice)
        } else {
            return nil
        }
    }
}

public extension LexerMachine {
    @inline(__always)
    func peak() -> Token.Source.Element? {
        return peak(at: tokenEnd)
    }

    @inline(__always)
    func peak(at index: Int) -> Token.Source.Element? {
        if index >= boundary {
            return nil
        }

        return source[source.index(source.startIndex, offsetBy: index)]
    }

    @inline(__always)
    func peak(for len: Int) -> Token.Source.SubSequence? {
        return peak(at: tokenEnd, for: len)
    }

    @inline(__always)
    func peak(at: Int, for len: Int) -> Token.Source.SubSequence? {
        return peak(from: at, to: at + len)
    }

    @inline(__always)
    func peak(from start: Int, to end: Int) -> Token.Source.SubSequence? {
        if end > boundary {
            return nil
        }

        return source[start ..< end]
    }
}
