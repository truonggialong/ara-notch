import Foundation

/// Fitting what an agent said onto a notice.
public enum AgentNoticeText {
    /// The message on at most two lines of so many characters, broken between words; what
    /// does not fit is cut and marked with an ellipsis.
    public static func lines(of message: String, width: Int = 30) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in message.split(whereSeparator: \.isWhitespace) {
            if line.isEmpty {
                line = String(word)
            } else if line.count + 1 + word.count <= width {
                line += " " + word
            } else {
                lines.append(line)
                line = String(word)
            }
        }
        if !line.isEmpty { lines.append(line) }
        guard lines.count > 2 else { return lines }
        return [lines[0], lines[1] + "…"]
    }
}
