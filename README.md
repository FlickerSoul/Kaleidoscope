# Kaleidoscope

This is a lexer inspired by [logos](https://github.com/maciejhirsz/logos). It utilizes swift macros enable easy creation. 

## Example

```swift
import Kaleidoscope

let lambda: (inout LexerMachine<Tokens>) -> Substring = { (lex: inout LexerMachine<Tokens>) in lex.slice }

@kaleidoscope(skip: " |\t|\n")
enum Tokens {
    @token("not")
    case Not

    @regex("very")
    case Very

    @token("tokenizer")
    case Tokenizer

    // you could feed a closure directly to `onMatch` but swift doesn't like it for some reason...?
    @regex("[a-zA-Z_][a-zA-Z1-9$_]*?", onMatch: lambda) 
    case Identifier(Substring)
}


for token in Tokens.lexer(source: "not a very fast tokenizer").map({ try! $0.get() }) {
    print(token)
}
```

The output will be 

```text
Not
Identifier("a")
Very
Identifier("fast")
Tokenizer
```

## Idea

The project is provides three macros: `@kaleidoscope`, `regex`, and `token`, and they work together to generate conformance to `LexerProtocol` for the decorated  enums. `regex` takes in a regex expression for matching and `token` takes a string for excat matching. In addition, they can take a `onMatch` callback and a `priority` integer. The callback has access to token string slice and can futher transform it to whatever type required by the enum case. The priority are calculated by from the expression by default. However, if two exprssions have the same weight, manual specification is required to resolve the conflict. 

Internally, all regex expressions and token strings are converted into a single finite automata. The finite automata consumes one character from the input at a time, until it reaches an token match or an error. This machanism is simple but works slowly. Future improvements can be established on this issue. 

## Note 

This package uses an internal Swift package [`_RegexParser`](https://github.com/apple/swift-experimental-string-processing) included in the experimental string processing lib. Please check out the github packe for compatibility. Due to its being experimental, this library can break in the future. 

## Furture Improvements

- [ ] faster tokenization optomization 
- [ ] cleaner code generation 
- [ ] cleaner interface
