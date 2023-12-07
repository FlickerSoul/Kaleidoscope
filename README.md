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

    // you could put lambda directly here but they type checking doesn't seem to work very well?
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
