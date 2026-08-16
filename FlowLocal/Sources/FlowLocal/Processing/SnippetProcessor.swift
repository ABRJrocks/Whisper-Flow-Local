import AppKit
import Foundation

/// Snippet expansion (spec §16). A snippet fires when the whole normalized dictation
/// matches a trigger/alias, or inline when the snippet allows it.
struct SnippetProcessor: Sendable {
    let snippets: [SnippetRecord]

    /// Returns expanded text and whether a sensitive snippet fired.
    func process(_ text: String) -> (text: String, usedSensitive: Bool) {
        let normalized = normalize(text)
        // Full-match expansion
        for snippet in snippets {
            let triggers = [snippet.trigger] + snippet.aliases
            if triggers.contains(where: { normalize($0) == normalized }) {
                return (expandPlaceholders(snippet.expansion), snippet.isSensitive)
            }
        }
        // Inline expansion for snippets that opted in
        var result = text
        var sensitive = false
        for snippet in snippets where snippet.allowInline {
            for trigger in [snippet.trigger] + snippet.aliases {
                if let range = result.range(of: trigger, options: [.caseInsensitive]) {
                    result.replaceSubrange(range, with: expandPlaceholders(snippet.expansion))
                    sensitive = sensitive || snippet.isSensitive
                }
            }
        }
        return (result, sensitive)
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func expandPlaceholders(_ expansion: String) -> String {
        var result = expansion
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        result = result.replacingOccurrences(of: "{{date}}", with: dateFormatter.string(from: now))
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        result = result.replacingOccurrences(of: "{{time}}", with: dateFormatter.string(from: now))
        dateFormatter.dateStyle = .medium
        result = result.replacingOccurrences(of: "{{datetime}}", with: dateFormatter.string(from: now))
        if result.contains("{{clipboard}}") {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{{clipboard}}", with: clip)
        }
        result = result.replacingOccurrences(of: "{{newline}}", with: "\n")
        // {{cursor}} is resolved by the paste layer; leave it in place here.
        return result
    }
}
