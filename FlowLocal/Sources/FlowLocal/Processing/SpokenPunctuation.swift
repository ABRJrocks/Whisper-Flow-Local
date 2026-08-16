import Foundation

/// Explicit spoken punctuation commands (spec §13.3). Off by default; Apple's engine
/// already punctuates — this catches explicit commands like "new paragraph".
enum SpokenPunctuation {
    private static let replacements: [(spoken: String, written: String)] = [
        ("new paragraph", "\n\n"),
        ("new line", "\n"),
        ("open quote", "\u{201C}"),
        ("close quote", "\u{201D}"),
        ("open parenthesis", "("),
        ("close parenthesis", ")"),
        ("question mark", "?"),
        ("exclamation mark", "!"),
        ("exclamation point", "!"),
        ("semicolon", ";"),
    ]

    static func process(_ text: String) -> String {
        var result = text
        for (spoken, written) in replacements {
            // Match the command with optional surrounding punctuation the ASR may add.
            let pattern = "[,.]?\\s*\\b\(NSRegularExpression.escapedPattern(for: spoken))\\b[,.]?\\s*"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: written)
            let replaced = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
            // For punctuation marks, glue to the previous word; for newlines keep as-is.
            result = replaced
        }
        // Clean space before punctuation introduced by replacement.
        result = result.replacingOccurrences(of: " ?", with: "?")
        result = result.replacingOccurrences(of: " !", with: "!")
        result = result.replacingOccurrences(of: " ;", with: ";")
        return result
    }
}
