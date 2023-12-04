//
//  Lexer.swift
//
//
//  Created by Larry Zeng on 12/4/23.
//

enum LexerError: Error {
    case SourceBoundExceeded
    case EmptyToken
}

protocol Lexer {
    associatedtype Token: Lexer
    typealias Source = String
    typealias TokenStream = [Token]
    typealias Slice = Substring

    static func lex(_ lexer: inout LexerMachine<Self>) throws
    func lexer(source: Source) -> LexerMachine<Token>
}

struct LexerMachine<Token: Lexer> {
    let source: Token.Source
    var token: Token?
    var tokenStart: Int
    var tokenEnd: Int

    @inlinable
    var boundary: Int {
        return source.count
    }

    @inlinable
    var span: Range<Int> {
        return tokenStart ..< tokenEnd
    }

    @inlinable
    var slice: Token.Slice {
        let start = source.startIndex
        let range = source.index(start, offsetBy: tokenStart) ..< source.index(start, offsetBy: tokenEnd)
        return source[range]
    }

    @inlinable
    var remainder: Token.Slice {
        let start = source.startIndex
        let range = source.index(start, offsetBy: tokenEnd) ..< source.index(start, offsetBy: boundary)

        return source[range]
    }

    @inlinable
    public func branch() -> Self {
        return .init(source: source, token: nil, tokenStart: 0, tokenEnd: 0)
    }

    @inlinable
    public mutating func bump(by: Int) {
        tokenEnd += by
        assert(tokenEnd <= boundary, "Token Pointer Bump Exceed Source Boundary")
    }

    @inlinable
    public mutating func bump() {
        bump(by: 1)
    }

    mutating func take() throws -> Token {
        guard let token = token else {
            throw LexerError.EmptyToken
        }

        return token
    }

    var spanned: SpannedLexerIter<Token> {
        return .init(lexer: self)
    }

    var sliced: SlicedLexerIter<Token> {
        return .init(lexer: self)
    }

    var spannedAndSliced: SpannedSlicedLexerIter<Token> {
        return .init(lexer: self)
    }
}

extension LexerMachine: IteratorProtocol {
    @inlinable
    public mutating func next() -> Result<Token, Error>? {
        tokenStart = tokenEnd

        if tokenEnd == boundary {
            return nil
        }

        return Result(catching: {
            try Token.lex(&self)
            return try self.take()
        })
    }
}

struct SpannedLexerIter<Token: Lexer>: IteratorProtocol {
    var lexer: LexerMachine<Token>

    public mutating func next() -> Result<(Token, Range<Int>), Error>? {
        lexer.tokenStart = lexer.tokenEnd

        if lexer.tokenEnd == lexer.boundary {
            return nil
        }

        return Result(catching: {
            try Token.lex(&lexer)
            return try (lexer.take(), lexer.span)
        })
    }
}

struct SlicedLexerIter<Token: Lexer>: IteratorProtocol {
    var lexer: LexerMachine<Token>

    public mutating func next() -> Result<(Token, Substring), Error>? {
        lexer.tokenStart = lexer.tokenEnd

        if lexer.tokenEnd == lexer.boundary {
            return nil
        }

        return Result(catching: {
            try Token.lex(&lexer)
            return try (lexer.take(), lexer.slice)
        })
    }
}

struct SpannedSlicedLexerIter<Token: Lexer>: IteratorProtocol {
    var lexer: LexerMachine<Token>

    public mutating func next() -> Result<(Token, Range<Int>, Substring), Error>? {
        lexer.tokenStart = lexer.tokenEnd

        if lexer.tokenEnd == lexer.boundary {
            return nil
        }

        return Result(catching: {
            try Token.lex(&lexer)
            return try (lexer.take(), lexer.span, lexer.slice)
        })
    }
}
