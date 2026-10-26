/// A run of source text with one highlighting colour.
public struct CodeToken: Equatable, Sendable {
    public enum Kind: Sendable {
        case plain
        case keyword
        case string
        case comment
        case number
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Splits source text into tokens for highlighting. Language-agnostic: it knows the comment,
/// string and number shapes shared by common languages, not any grammar. The tokens always
/// concatenate back to exactly the input.
public enum CodeTokenizer {
    private static let keywords: Set<String> = [
        // Declarations
        "func", "function", "def", "fn", "class", "struct", "enum", "interface", "protocol", "extension",
        "trait", "impl", "type", "typealias", "namespace", "package", "module", "import", "from", "export",
        "using", "include", "let", "var", "const", "val", "static", "final", "public", "private",
        "protected", "internal", "fileprivate", "open", "override", "abstract", "virtual", "async", "await",
        // Control flow
        "if", "else", "elif", "for", "while", "do", "switch", "case", "default", "break", "continue",
        "return", "yield", "guard", "defer", "try", "catch", "throw", "throws", "finally", "in", "of",
        "is", "as", "new", "delete", "match", "where", "with", "lambda", "pass", "raise", "except",
        // Values and types
        "true", "false", "nil", "null", "None", "True", "False", "undefined", "self", "this", "super",
        "void", "int", "float", "double", "bool", "string", "char", "long", "short", "unsigned",
        // SQL
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE",
        "TABLE", "JOIN", "ON", "AND", "OR", "NOT", "NULL", "ORDER", "BY", "GROUP", "LIMIT",
    ]

    public static func tokenize(_ text: String) -> [CodeToken] {
        let characters = Array(text)
        var tokens: [CodeToken] = []
        var plain = ""
        var index = 0
        // True until the first non-blank character of a line; `#` and `--` are comments only there.
        var isAtLineStart = true

        func flushPlain() {
            if !plain.isEmpty {
                tokens.append(CodeToken(kind: .plain, text: plain))
                plain = ""
            }
        }

        func emit(_ kind: CodeToken.Kind, upTo end: Int) {
            flushPlain()
            tokens.append(CodeToken(kind: kind, text: String(characters[index..<end])))
            index = end
        }

        func endOfLine(from start: Int) -> Int {
            var end = start
            while end < characters.count, !characters[end].isNewline { end += 1 }
            return end
        }

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let wasAtLineStart = isAtLineStart

            if character.isNewline {
                isAtLineStart = true
            } else if !character.isWhitespace {
                isAtLineStart = false
            }

            if character == "/", next == "/" {
                emit(.comment, upTo: endOfLine(from: index))
            } else if character == "/", next == "*" {
                var end = index + 2
                while end < characters.count, !(characters[end - 1] == "*" && characters[end] == "/" && end > index + 2) {
                    end += 1
                }
                emit(.comment, upTo: min(end + 1, characters.count))
            } else if wasAtLineStart, character == "#" || (character == "-" && next == "-") {
                emit(.comment, upTo: endOfLine(from: index))
            } else if character == "\"" || character == "'" || character == "`" {
                emit(.string, upTo: endOfString(in: characters, from: index))
            } else if character.isASCII, character.isNumber, !isIdentifierCharacter(previous(in: characters, index)) {
                emit(.number, upTo: endOfNumber(in: characters, from: index))
            } else if character.isLetter || character == "_" {
                var end = index
                while end < characters.count, isIdentifierCharacter(characters[end]) { end += 1 }
                let word = String(characters[index..<end])
                if keywords.contains(word) {
                    emit(.keyword, upTo: end)
                } else {
                    plain += word
                    index = end
                }
            } else {
                plain.append(character)
                index += 1
            }
        }
        flushPlain()
        return tokens
    }

    /// Index just past the closing quote; an unterminated string stops at the end of its line.
    private static func endOfString(in characters: [Character], from start: Int) -> Int {
        let quote = characters[start]
        var end = start + 1
        while end < characters.count {
            let character = characters[end]
            if character == "\\" {
                end += 2
            } else if character == quote {
                return end + 1
            } else if character.isNewline {
                return end
            } else {
                end += 1
            }
        }
        return min(end, characters.count)
    }

    private static func endOfNumber(in characters: [Character], from start: Int) -> Int {
        var end = start + 1
        let isHex = characters[start] == "0" && end < characters.count && (characters[end] == "x" || characters[end] == "X")
        if isHex { end += 1 }
        while end < characters.count {
            let character = characters[end]
            let isDigit = character.isASCII && (isHex ? character.isHexDigit : character.isNumber)
            // A dot belongs to the number only when a digit follows, so "3.foo" stays "3" + ".foo".
            let isDecimalPoint = character == "." && !isHex && end + 1 < characters.count
                && characters[end + 1].isASCII && characters[end + 1].isNumber
            guard isDigit || character == "_" || isDecimalPoint else { break }
            end += 1
        }
        return end
    }

    private static func previous(in characters: [Character], _ index: Int) -> Character? {
        index > 0 ? characters[index - 1] : nil
    }

    private static func isIdentifierCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }
}
