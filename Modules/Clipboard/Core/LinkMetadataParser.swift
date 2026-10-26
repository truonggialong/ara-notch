import Foundation

/// What a web page says about itself for link previews.
public struct LinkMetadata: Equatable, Sendable {
    public var title: String?
    public var imageURL: URL?

    public init(title: String? = nil, imageURL: URL? = nil) {
        self.title = title
        self.imageURL = imageURL
    }
}

/// Extracts the title and preview image from a page's HTML. Tolerant of sloppy markup; it scans
/// for the few tags it needs instead of parsing the document.
public enum LinkMetadataParser {
    /// Only the beginning of the document is examined; the tags of interest live in `<head>`.
    public static let examinedLength = 512_000
    public static let maxTitleLength = 200

    public static func parse(html: String, baseURL: URL) -> LinkMetadata {
        let sample = String(html.prefix(examinedLength))
        let meta = metaValues(in: sample)

        let title = [meta["og:title"], meta["twitter:title"], titleTag(in: sample)]
            .compactMap { $0.flatMap(cleanTitle) }
            .first
        let imageURL = [meta["og:image"], meta["twitter:image"]]
            .compactMap { $0.flatMap { resolveImage($0, baseURL: baseURL) } }
            .first
        return LinkMetadata(title: title, imageURL: imageURL)
    }

    // MARK: - Tags

    /// `property` or `name` → `content` for every `<meta>` tag; the first non-blank value wins.
    private static func metaValues(in html: String) -> [String: String] {
        var values: [String: String] = [:]
        var searchStart = html.startIndex
        while let open = html.range(of: "<meta", options: .caseInsensitive, range: searchStart..<html.endIndex) {
            let (attributes, end) = parseAttributes(in: html, from: open.upperBound)
            searchStart = end
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"],
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  values[key] == nil
            else { continue }
            values[key] = content
        }
        return values
    }

    /// Reads `name="value"` pairs up to the closing `>` of a tag. Values may be double-quoted,
    /// single-quoted or bare. Returns the pairs (names lowercased) and the index after the tag.
    private static func parseAttributes(
        in html: String, from start: String.Index
    ) -> (attributes: [String: String], end: String.Index) {
        var attributes: [String: String] = [:]
        var index = start

        func skipWhitespace() {
            while index < html.endIndex, html[index].isWhitespace { index = html.index(after: index) }
        }

        while index < html.endIndex {
            skipWhitespace()
            guard index < html.endIndex else { break }
            if html[index] == ">" {
                return (attributes, html.index(after: index))
            }
            if html[index] == "/" {
                index = html.index(after: index)
                continue
            }

            let nameStart = index
            while index < html.endIndex, !html[index].isWhitespace, !"=>/".contains(html[index]) {
                index = html.index(after: index)
            }
            let name = html[nameStart..<index].lowercased()
            skipWhitespace()
            guard index < html.endIndex, html[index] == "=" else {
                if name.isEmpty, index < html.endIndex { index = html.index(after: index) }
                continue
            }
            index = html.index(after: index)
            skipWhitespace()
            guard index < html.endIndex else { break }

            let value: Substring
            if html[index] == "\"" || html[index] == "'" {
                let quote = html[index]
                let valueStart = html.index(after: index)
                guard let close = html[valueStart...].firstIndex(of: quote) else {
                    return (attributes, html.endIndex)
                }
                value = html[valueStart..<close]
                index = html.index(after: close)
            } else {
                let valueStart = index
                while index < html.endIndex, !html[index].isWhitespace, html[index] != ">" {
                    index = html.index(after: index)
                }
                value = html[valueStart..<index]
            }
            if attributes[name] == nil {
                attributes[name] = String(value)
            }
        }
        return (attributes, html.endIndex)
    }

    /// The text between `<title …>` and `</title>`; nil when the tag is missing or never closed.
    private static func titleTag(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let openEnd = html[open.upperBound...].firstIndex(of: ">"),
              let close = html.range(
                  of: "</title", options: .caseInsensitive, range: html.index(after: openEnd)..<html.endIndex)
        else { return nil }
        return String(html[html.index(after: openEnd)..<close.lowerBound])
    }

    // MARK: - Values

    private static func cleanTitle(_ raw: String) -> String? {
        let collapsed = decodeEntities(raw)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : String(collapsed.prefix(maxTitleLength))
    }

    /// Only web addresses are accepted; `javascript:`, `data:` and `file:` values are dropped.
    private static func resolveImage(_ raw: String, baseURL: URL) -> URL? {
        let value = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
        else { return nil }
        return url
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    ]

    /// Decodes the common named entities and numeric ones; anything else is left as written.
    private static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        var rest = Substring(string)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let after = rest[rest.index(after: ampersand)...]
            // An entity is short; a far-away semicolon belongs to something else.
            if let semicolon = after.prefix(12).firstIndex(of: ";"),
               let decoded = decodeEntity(String(after[..<semicolon])) {
                result += decoded
                rest = after[after.index(after: semicolon)...]
            } else {
                result += "&"
                rest = after
            }
        }
        return result + rest
    }

    private static func decodeEntity(_ name: String) -> String? {
        if let named = namedEntities[name] { return named }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let code = digits.hasPrefix("x") || digits.hasPrefix("X")
            ? UInt32(digits.dropFirst(), radix: 16)
            : UInt32(digits, radix: 10)
        return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }
}
