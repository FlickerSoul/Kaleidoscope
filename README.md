# Kaleidoscope

This is a lexer inspired by [logos](https://github.com/maciejhirsz/logos). It utilizes swift macros enable easy creation. 

## Example

```swift
import Kaleidoscope

@kaleidoscope(skip: " |\t|\n")
enum Tokens {
    @token("not")
    case Not
    
    @regex("very")
    case Very
    
    @token("tokenizer")
    case Tokenizer
    
    @regex("[a-zA-Z_][a-zA-Z1-9$_]*?")
    case Identifier
}

for token in Tokens.lexer("not a very fast tokenizer").map { $0.get } {
    print(token)
}
```
