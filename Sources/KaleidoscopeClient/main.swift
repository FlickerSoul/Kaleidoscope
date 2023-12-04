import Kaleidoscope

@kaleidoscope
enum Token {
    @regex("aa")
    case AA

    @regex("bb")
    case B
}

let result = Token.lexer(source: "aabb")
print(result)
