@main
enum Tokenizer {
    static func main() {
        let result = Token.lexer(source: "aabb")
        print(result)
    }
}
