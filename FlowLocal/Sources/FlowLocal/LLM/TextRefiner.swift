import Foundation

/// Payload for the fast dictation-polish LLM (spec §14.1).
struct RefinePayload: Codable, Sendable {
    var rawTranscript: String
    var language: String
    var appCategory: String
    var formality: Double
    var concision: Double
    var emojiAllowed: Bool
    var customInstructions: String
    var textBeforeCursor: String?
    var protectedTerms: [String]
}

/// Structured Command Mode action (spec §14.2). The parser rejects unknown actions.
struct CommandAction: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case replace, insert, keystroke, none
    }
    var action: Kind
    var text: String
    var keystroke: String? // "enter" | "tab" | "backspace"
}

/// Local text-refinement model. Implementations must be conservative and local-only.
protocol TextRefiner: AnyObject, Sendable {
    var modelID: String { get }
    var isLoaded: Bool { get async }
    func load() async throws
    func unload() async
    /// Clean up a raw transcript. Throws on failure; caller falls back to rule-processed text.
    func refine(_ payload: RefinePayload) async throws -> String
    /// Interpret a Command Mode instruction against selected text. Strict JSON out.
    func command(instruction: String, selectedText: String, appCategory: String, language: String) async throws -> CommandAction
}

/// Guardrails applied to every LLM output (spec §13.7).
enum LLMGuardrails {
    /// Tokens that must survive refinement: numbers, currency, emails, URLs.
    static func protectedTokens(in text: String) -> [String] {
        var tokens: [String] = []
        let patterns = [
            #"\$?\d[\d,]*(\.\d+)?%?"#,                       // numbers, currency, percents
            #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, // emails
            #"https?://\S+|www\.\S+|\b\S+\.(com|org|net|io|dev|pk)\b"#, // URLs/domains
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) { tokens.append(String(text[r])) }
            }
        }
        return tokens
    }

    /// Validate LLM output against the input. Returns nil when output should be rejected.
    static func validate(output rawOutput: String, input: String, allowExpansion: Bool = false) -> String? {
        var output = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip common wrappers: markdown fences, surrounding quotes, "Here is..." preambles.
        if output.hasPrefix("```") {
            output = output
                .replacingOccurrences(of: #"^```[a-z]*\n?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if output.hasPrefix("\"") && output.hasSuffix("\"") && output.count > 2 {
            output = String(output.dropFirst().dropLast())
        }
        guard !output.isEmpty else { return nil }
        if !allowExpansion && output.count > Int(Double(input.count) * 2.5) + 40 { return nil }
        for token in protectedTokens(in: input) where !output.contains(token) {
            return nil
        }
        return output
    }
}
