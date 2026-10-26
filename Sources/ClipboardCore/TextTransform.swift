import Foundation

/// A tool that rewrites the text of a clip: cleaning it up, changing its letter case or naming
/// style, reformatting JSON, or encoding and decoding it.
public enum TextTransform: String, CaseIterable, Sendable {
    case trimWhitespace
    case removeEmptyLines
    case joinLines
    case sortLines
    case uniqueLines
    case uppercase
    case lowercase
    case titleCase
    case camelCase
    case snakeCase
    case kebabCase
    case prettyJSON
    case minifyJSON
    case base64Encode
    case base64Decode
    case urlEncode
    case urlDecode

    /// Tools are listed group by group, in the order of the cases above.
    public enum Group: CaseIterable, Sendable {
        case cleanup
        case letterCase
        case naming
        case json
        case encoding
    }

    public var group: Group {
        switch self {
        case .trimWhitespace, .removeEmptyLines, .joinLines, .sortLines, .uniqueLines: .cleanup
        case .uppercase, .lowercase, .titleCase: .letterCase
        case .camelCase, .snakeCase, .kebabCase: .naming
        case .prettyJSON, .minifyJSON: .json
        case .base64Encode, .base64Decode, .urlEncode, .urlDecode: .encoding
        }
    }

    public static func tools(in group: Group) -> [TextTransform] {
        allCases.filter { $0.group == group }
    }

    /// The rewritten text, or nil when the tool cannot work on this text: it is blank, is not
    /// valid JSON, or does not decode to text.
    public func apply(to text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch self {
        case .trimWhitespace:
            let trimmed = Self.lines(of: text).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = trimmed.firstIndex(where: { !$0.isEmpty }),
                  let last = trimmed.lastIndex(where: { !$0.isEmpty })
            else { return nil }
            return trimmed[first...last].joined(separator: "\n")
        case .removeEmptyLines:
            return Self.lines(of: text).filter { !Self.isBlank($0) }.joined(separator: "\n")
        case .joinLines:
            return Self.lines(of: text)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .sortLines:
            return Self.lines(of: text).sorted(by: Self.ordersBefore).joined(separator: "\n")
        case .uniqueLines:
            var seen = Set<String>()
            return Self.lines(of: text).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return text.capitalized
        case .camelCase:
            return Self.renamed(text) { words in
                words.enumerated().map { $0.offset == 0 ? $0.element.lowercased() : $0.element.capitalized }.joined()
            }
        case .snakeCase:
            return Self.renamed(text) { $0.map { $0.lowercased() }.joined(separator: "_") }
        case .kebabCase:
            return Self.renamed(text) { $0.map { $0.lowercased() }.joined(separator: "-") }
        case .prettyJSON:
            return Self.reformattedJSON(text, pretty: true)
        case .minifyJSON:
            return Self.reformattedJSON(text, pretty: false)
        case .base64Encode:
            return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            return Self.base64Decoded(text)
        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved)
        case .urlDecode:
            return text.removingPercentEncoding
        }
    }

    // MARK: - Lines

    /// The lines of the text. A line break at the very end does not start another line.
    private static func lines(of text: String) -> [String] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.count > 1, lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// Case does not matter and numbers order by value; equal lines fall back to exact order.
    private static func ordersBefore(_ a: String, _ b: String) -> Bool {
        switch a.compare(b, options: [.caseInsensitive, .numeric]) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: a < b
        }
    }

    // MARK: - Naming styles

    /// Rewrites each line as one identifier built from its words. Nil when no line has a word.
    private static func renamed(_ text: String, join: ([String]) -> String) -> String? {
        var foundWords = false
        let renamed = lines(of: text).map { line -> String in
            let words = words(in: line)
            guard !words.isEmpty else { return line }
            foundWords = true
            return join(words)
        }
        return foundWords ? renamed.joined(separator: "\n") : nil
    }

    /// Splits on anything that is not a letter or digit, and inside a run where the letter case
    /// marks a new word: `userName`, `HTTPServer`, `url2Fast`.
    static func words(in line: String) -> [String] {
        var words: [String] = []
        var current: [Character] = []
        func flush() {
            if !current.isEmpty {
                words.append(String(current))
                current = []
            }
        }
        let characters = Array(line)
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                flush()
                continue
            }
            if let previous = current.last, character.isUppercase {
                let next = characters.indices.contains(index + 1) ? characters[index + 1] : nil
                let endsAcronym = previous.isUppercase && (next?.isLowercase ?? false)
                if previous.isLowercase || previous.isNumber || endsAcronym {
                    flush()
                }
            }
            current.append(character)
        }
        flush()
        return words
    }

    // MARK: - JSON

    /// Re-spaces a JSON object or array without touching its tokens, so key order and the way
    /// numbers are written survive. Nil when the text is not valid JSON.
    private static func reformattedJSON(_ text: String, pretty: Bool) -> String? {
        guard (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil else { return nil }
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = 0

        func isSpace(_ scalar: Unicode.Scalar) -> Bool {
            scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
        }
        func newLine() {
            guard pretty else { return }
            output.append("\n")
            output.append(contentsOf: String(repeating: "  ", count: depth).unicodeScalars)
        }

        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            if inString {
                output.append(scalar)
                if isEscaped {
                    isEscaped = false
                } else if scalar == "\\" {
                    isEscaped = true
                } else if scalar == "\"" {
                    inString = false
                }
                continue
            }
            switch scalar {
            case "\"":
                inString = true
                output.append(scalar)
            case "{", "[":
                output.append(scalar)
                var next = index
                while next < scalars.count, isSpace(scalars[next]) {
                    next += 1
                }
                if next < scalars.count, scalars[next] == "}" || scalars[next] == "]" {
                    // An empty object or array stays on one line.
                    output.append(scalars[next])
                    index = next + 1
                } else {
                    depth += 1
                    newLine()
                }
            case "}", "]":
                depth -= 1
                newLine()
                output.append(scalar)
            case ",":
                output.append(scalar)
                newLine()
            case ":":
                output.append(scalar)
                if pretty {
                    output.append(" ")
                }
            default:
                if !isSpace(scalar) {
                    output.append(scalar)
                }
            }
        }
        return String(output)
    }

    // MARK: - Encoding

    private static let urlUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Accepts line breaks, the URL-safe alphabet and missing padding. Nil unless the bytes are text.
    private static func base64Decoded(_ text: String) -> String? {
        var encoded = String(text.filter { !$0.isWhitespace })
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 {
            encoded.append("=")
        }
        guard let data = Data(base64Encoded: encoded), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
