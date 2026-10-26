import Foundation
import FoundationModels

/// Summarises and rewrites text with the model Apple Intelligence keeps on this Mac. Nothing
/// leaves the Mac and nothing is paid for; it only works where Apple Intelligence is switched
/// on and its model has been downloaded.
@MainActor
public final class TextAssistant {
    public enum Action: String, CaseIterable, Sendable {
        case summarize
        case rewrite

        var instructions: String {
            switch self {
            case .summarize:
                "You summarize text for a clipboard manager. Reply with only the summary, in the same language as the text, in at most three sentences."
            case .rewrite:
                "You rewrite text for a clipboard manager so it reads clearly and correctly. Keep the meaning, the language and the tone. Reply with only the rewritten text."
            }
        }

        var request: String {
            switch self {
            case .summarize: "Summarize the following text:\n\n"
            case .rewrite: "Rewrite the following text:\n\n"
            }
        }
    }

    /// Why the model cannot be used now, in a word; nil when it can.
    public enum Unavailable: String, Sendable {
        case deviceNotEligible
        case notEnabled
        case modelNotReady
        case other
    }

    /// Longer text does not fit what the model reads at once.
    public static let maxLength = 12_000

    public init() {}

    public var unavailable: Unavailable? {
        // The model came with macOS 26; on an older system there is none.
        guard #available(macOS 26.0, *) else { return .deviceNotEligible }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .other
            }
        }
    }

    /// The actions on offer right now: all of them, or none while the model cannot be used.
    public var availableActions: [Action] {
        unavailable == nil ? Action.allCases : []
    }

    /// Answers on the main actor with the model's text, or nil when it could not answer.
    public func run(_ action: Action, on text: String, completion: @escaping @MainActor (String?) -> Void) {
        guard unavailable == nil, #available(macOS 26.0, *) else {
            completion(nil)
            return
        }
        let prompt = action.request + String(text.prefix(Self.maxLength))
        let instructions = action.instructions
        Task {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let answer = try await session.respond(to: prompt)
                completion(answer.content)
            } catch {
                completion(nil)
            }
        }
    }
}
