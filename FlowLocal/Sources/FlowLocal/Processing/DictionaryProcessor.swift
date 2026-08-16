import Foundation

/// Applies user dictionary replacements: longest-match-first, whole-word aware,
/// case-sensitive when requested (spec §15.2).
struct DictionaryProcessor: Sendable {
    let entries: [DictionaryEntryRecord]

    func process(_ text: String) -> String {
        var result = text
        // Protected terms and higher priority first, then longer spoken forms first.
        let ordered = entries
            .filter { ($0.spokenForm ?? "").isEmpty == false }
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return ($0.spokenForm?.count ?? 0) > ($1.spokenForm?.count ?? 0)
            }
        for entry in ordered {
            guard let spoken = entry.spokenForm, !spoken.isEmpty else { continue }
            result = replace(in: result, spoken: spoken, written: entry.writtenForm,
                             caseSensitive: entry.caseSensitive, wholeWord: entry.wholeWord)
        }
        return result
    }

    private func replace(in text: String, spoken: String, written: String, caseSensitive: Bool, wholeWord: Bool) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: spoken)
        let pattern = wholeWord ? "\\b\(escaped)\\b" : escaped
        var options: NSRegularExpression.Options = []
        if !caseSensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text, range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: written)
        )
    }
}
