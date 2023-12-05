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

public protocol LexerProtocol {
    associatedtype TokenType: LexerProtocol
    typealias Source = String
    typealias TokenStream = [TokenType]
    typealias Slice = Substring

    static func lex(_ lexer: inout LexerMachine<Self>) throws
    static func lexer(source: Source) -> LexerMachine<Self>
}

public struct LexerMachine<Token: LexerProtocol> {
    let source: Token.Source
    var token: Result<Token, Error>?
    var tokenStart: Int
    var tokenEnd: Int

    public init(source: LexerProtocol.Source, token: Result<Token, Error>? = nil, tokenStart: Int = 0, tokenEnd: Int = 0) {
        self.source = source
        self.token = token
        self.tokenStart = tokenStart
        self.tokenEnd = tokenEnd
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
    public var slice: Token.Slice {
        let start = source.startIndex
        let range = source.index(start, offsetBy: tokenStart) ..< source.index(start, offsetBy: tokenEnd)
        return source[range]
    }

    @inline(__always)
    public var remainder: Token.Slice {
        let start = source.startIndex
        let range = source.index(start, offsetBy: tokenEnd) ..< source.index(start, offsetBy: boundary)

        return source[range]
    }

    @inline(__always)
    public func branch() -> Self {
        return .init(source: source, token: nil, tokenStart: 0, tokenEnd: 0)
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
    mutating func take() throws -> Token {
        switch token {
        case .none:
            throw LexerError.EmptyToken
        case .some(let result):
            switch result {
            case .success(let token):
                self.token = nil
                return token
            case .failure(let error):
                throw error
            }
        }
    }

    @inline(__always)
    public var spanned: SpannedLexerIter<Token> {
        return .init(lexer: self)
    }

    @inline(__always)
    public var sliced: SlicedLexerIter<Token> {
        return .init(lexer: self)
    }

    @inline(__always)
    public var spannedAndSliced: SpannedSlicedLexerIter<Token> {
        return .init(lexer: self)
    }

    @inline(__always)
    public mutating func setToken(_ token: Token) throws {
        guard self.token == nil else {
            throw LexerError.DuplicatedToken
        }
        self.token = .success(token)
    }

    @inline(__always)
    public mutating func error() {
        token = .failure(LexerError.NotMatch)
    }

    @inline(__always)
    public mutating func skip() throws {
        if tokenStart == tokenEnd {
            tokenEnd = tokenEnd + 1
            tokenStart = tokenEnd
        } else {
            reset()
        }
        try Token.lex(&self)
    }
}

extension LexerMachine: Sequence, IteratorProtocol {
    public mutating func next() -> Result<Token, Error>? {
        tokenStart = tokenEnd

        if tokenEnd == boundary {
            return nil
        }

        let result = Result(catching: {
            try Token.lex(&self)
            return try self.take()
        })

        return result
    }
}

public struct SpannedLexerIter<Token: LexerProtocol>: Sequence, IteratorProtocol {
    var lexer: LexerMachine<Token>

    public mutating func next() -> (Result<Token, Error>?, Range<Int>)? {
        lexer.tokenStart = lexer.tokenEnd

        if lexer.tokenEnd == lexer.boundary {
            return nil
        }

        return (lexer.next(), lexer.span)
    }
}

public struct SlicedLexerIter<Token: LexerProtocol>: Sequence, IteratorProtocol {
    var lexer: LexerMachine<Token>

    public mutating func next() -> (Result<Token, Error>?, Substring)? {
        lexer.tokenStart = lexer.tokenEnd

        if lexer.tokenEnd == lexer.boundary {
            return nil
        }

        return (lexer.next(), lexer.slice)
    }
}

public struct SpannedSlicedLexerIter<Token: LexerProtocol>: Sequence, IteratorProtocol {
    var lexer: LexerMachine<Token>

    public mutating func next() -> (Result<Token, Error>?, Range<Int>, Substring)? {
        lexer.tokenStart = lexer.tokenEnd

        if lexer.tokenEnd == lexer.boundary {
            return nil
        }

        return (lexer.next(), lexer.span, lexer.slice)
    }
}

public extension LexerMachine {
    @inline(__always)
    func peak() -> Character? {
        return peak(at: tokenEnd)
    }

    @inline(__always)
    func peak(at index: Int) -> Character? {
        if index == boundary {
            return nil
        }

        return source[source.index(source.startIndex, offsetBy: index)]
    }

    @inline(__always)
    func peak(from start: Int, to end: Int) -> Substring {
        let startIndex = source.startIndex
        let range = source.index(startIndex, offsetBy: start) ..< source.index(startIndex, offsetBy: end)
        return source[range]
    }
}
