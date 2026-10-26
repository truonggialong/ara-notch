import Foundation

/// Guesses whether copied text is source code, so the preview can highlight it.
/// A heuristic: it favours leaving prose alone over catching every snippet.
public enum CodeDetector {
    /// Only the beginning of the text is examined.
    public static let examinedLength = 4_000

    private static let declarationKeywords: Set<String> = [
        "func", "def", "class", "import", "from", "const", "let", "var", "function", "return",
        "public", "private", "struct", "enum", "interface", "package", "using", "fn", "#include",
    ]
    /// SQL statements, matched in upper case only, each with the word that normally follows.
    private static let sqlStatements: [(verb: String, companion: String)] = [
        ("SELECT", "FROM"), ("INSERT", "INTO"), ("UPDATE", "SET"), ("CREATE", "TABLE"), ("DELETE", "FROM"),
    ]
    private static let inlineSignals = ["{", "}", "=>", "->", "==", "!=", "()", ");", " = "]

    public static func looksLikeCode(_ text: String) -> Bool {
        let sample = String(text.prefix(examinedLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return false }
        let lines = sample.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return isJSON(sample, lineCount: lines.count)
            || isMarkup(sample)
            || isSQL(sample, lines: lines)
            || hasDeclarationWithSyntax(sample, lines: lines)
            || isMostlyStatementLines(lines)
    }

    private static func isJSON(_ sample: String, lineCount: Int) -> Bool {
        guard lineCount >= 2, sample.hasPrefix("{") || sample.hasPrefix("[") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(sample.utf8))) != nil
    }

    private static func isMarkup(_ sample: String) -> Bool {
        sample.hasPrefix("<") && (sample.contains("</") || sample.contains("/>"))
    }

    private static func isSQL(_ sample: String, lines: [String]) -> Bool {
        sqlStatements.contains { statement in
            lines.contains { startsWithWord($0, statement.verb) } && containsWord(sample, statement.companion)
        }
    }

    /// A line opening with a declaration keyword, backed by at least two different syntax signals.
    /// The keyword alone is not enough: "import thuế tăng 5%" is prose.
    private static func hasDeclarationWithSyntax(_ sample: String, lines: [String]) -> Bool {
        guard lines.contains(where: { line in declarationKeywords.contains { startsWithWord(line, $0) } }) else {
            return false
        }
        var signals = inlineSignals.filter(sample.contains).count
        for ending in [";", ":", ")"] where lines.contains(where: { $0.hasSuffix(ending) }) {
            signals += 1
        }
        return signals >= 2
    }

    /// Three or more lines, most of them ending like statements. At least one line must end in
    /// `;`, `{` or `}`: commas and parentheses alone also end the lines of a postal address.
    private static func isMostlyStatementLines(_ lines: [String]) -> Bool {
        guard lines.count >= 3 else { return false }
        let strong = lines.filter { $0.hasSuffix(";") || $0.hasSuffix("{") || $0.hasSuffix("}") }.count
        let weak = lines.filter { $0.hasSuffix(",") || $0.hasSuffix(")") }.count
        return strong >= 1 && Double(strong + weak) / Double(lines.count) >= 0.6
    }

    private static func startsWithWord(_ line: String, _ word: String) -> Bool {
        guard line.hasPrefix(word) else { return false }
        guard let next = line.dropFirst(word.count).first else { return true }
        return !(next.isLetter || next.isNumber || next == "_")
    }

    private static func containsWord(_ text: String, _ word: String) -> Bool {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).contains { $0 == word }
    }
}
