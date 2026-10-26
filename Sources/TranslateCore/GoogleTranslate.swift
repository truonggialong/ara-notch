import Foundation

/// The result of one translation.
public struct TranslatedText: Equatable, Sendable {
    public var text: String
    /// The language Google took the text to be in, e.g. "en".
    public var sourceLanguage: String?
}

/// Builds requests to, and reads answers from, the address Google's own translate page uses.
/// It needs no account. Google makes no promise about it: it can change or be blocked.
public enum GoogleTranslate {
    public static let maxLength = 5000
    static let endpoint = "https://translate.googleapis.com/translate_a/single"

    /// A request translating `text` into `target`, with the source language detected.
    /// The text travels in the request body, never in the address. Nil for blank or overlong text.
    public static func request(text: String, target: String) -> URLRequest? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.count <= maxLength, let url = URL(string: endpoint) else { return nil }

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let fields = [("client", "gtx"), ("sl", "auto"), ("tl", target), ("dt", "t"), ("q", text)]
        let body = fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        return request
    }

    /// Reads the answer: a list whose first element lists sentence pairs and whose third names
    /// the detected language. Nil when the answer is anything else, such as a block page.
    public static func parse(_ data: Data) -> TranslatedText? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = root.first as? [Any]
        else { return nil }
        let text = sentences
            .compactMap { ($0 as? [Any])?.first as? String }
            .joined()
        guard !text.isEmpty else { return nil }
        let source = root.count > 2 ? root[2] as? String : nil
        return TranslatedText(text: text, sourceLanguage: source)
    }
}

/// Which language to translate into: the main one, or the other one for text that is already
/// in the main language.
public struct TranslationPlan: Equatable, Sendable {
    public var target: String
    public var alternate: String?

    public init(target: String, alternate: String?) {
        self.target = target
        self.alternate = alternate
    }

    public var firstTarget: String { target }

    /// After the first translation: the language to translate into instead, when the text
    /// turned out to be in the main language already.
    public func retryTarget(detectedSource: String?) -> String? {
        guard let detectedSource, let alternate, Self.base(alternate) != Self.base(target),
              Self.base(detectedSource) == Self.base(target)
        else { return nil }
        return alternate
    }

    /// The language a translation shown in `current` is turned into by the swap button: the
    /// other language of the pair, or the main one when `current` is neither. Nil when there
    /// is no other language to go to.
    ///
    /// - Parameter source: the language the text was found to be in; a swap back into it
    ///   would change nothing, so none is offered.
    public func swapTarget(from current: String, source: String? = nil) -> String? {
        let other: String?
        if Self.base(current) != Self.base(target) {
            other = target
        } else if let alternate, Self.base(alternate) != Self.base(target) {
            other = alternate
        } else {
            other = nil
        }
        if let other, let source, Self.base(other) == Self.base(source) { return nil }
        return other
    }

    /// "zh-CN" and "zh-TW" are both "zh".
    private static func base(_ code: String) -> String {
        code.split(separator: "-").first.map { $0.lowercased() } ?? code.lowercased()
    }
}

public struct TranslateLanguage: Equatable, Identifiable, Sendable {
    public let code: String
    /// The language's own name for itself.
    public let name: String

    public var id: String { code }

    public static let all: [TranslateLanguage] = [
        TranslateLanguage(code: "vi", name: "Tiếng Việt"),
        TranslateLanguage(code: "en", name: "English"),
        TranslateLanguage(code: "zh-CN", name: "中文（简体）"),
        TranslateLanguage(code: "zh-TW", name: "中文（繁體）"),
        TranslateLanguage(code: "ja", name: "日本語"),
        TranslateLanguage(code: "ko", name: "한국어"),
        TranslateLanguage(code: "fr", name: "Français"),
        TranslateLanguage(code: "de", name: "Deutsch"),
        TranslateLanguage(code: "es", name: "Español"),
        TranslateLanguage(code: "ru", name: "Русский"),
        TranslateLanguage(code: "th", name: "ไทย"),
    ]

    public static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// The code a speech voice is asked for by: the language with its usual region.
    public static func voiceCode(for code: String) -> String {
        let regions = [
            "vi": "vi-VN", "en": "en-US", "ja": "ja-JP", "ko": "ko-KR", "fr": "fr-FR", "de": "de-DE",
            "es": "es-ES", "ru": "ru-RU", "th": "th-TH",
        ]
        return regions[code] ?? code
    }
}

/// Reads and writes the quick-translate settings.
public struct TranslateSettingsStore {
    public enum Key {
        public static let isEnabled = "translate.enabled"
        public static let target = "translate.target"
        public static let alternate = "translate.alternate"
        public static let smartSelection = "translate.smartSelection"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Off until switched on: the feature claims a global shortcut and sends the selected text to Google.
    /// Show a bar of actions beside text the user just selected, in any app.
    public var smartSelection: Bool {
        get { defaults.object(forKey: Key.smartSelection) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.smartSelection) }
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Key.isEnabled) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.isEnabled) }
    }

    /// The language text is translated into.
    public var target: String {
        get { language(forKey: Key.target) ?? "vi" }
        nonmutating set { defaults.set(newValue, forKey: Key.target) }
    }

    /// The language used for text that is already in `target`; nil for none.
    public var alternate: String? {
        get {
            // An empty string is the stored form of "none".
            if let stored = defaults.object(forKey: Key.alternate) as? String, stored.isEmpty { return nil }
            return language(forKey: Key.alternate) ?? "en"
        }
        nonmutating set { defaults.set(newValue ?? "", forKey: Key.alternate) }
    }

    private func language(forKey key: String) -> String? {
        guard let code = defaults.object(forKey: key) as? String,
              TranslateLanguage.all.contains(where: { $0.code == code })
        else { return nil }
        return code
    }
}
