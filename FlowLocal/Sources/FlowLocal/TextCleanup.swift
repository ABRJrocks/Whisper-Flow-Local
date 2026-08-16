import Foundation

/// Deterministic post-ASR cleanup. The OS transcriber already handles punctuation
/// and capitalization; this is the safety net plus context-aware joining.
enum TextCleanup {
    /// Trim, collapse internal runs of spaces, capitalize first letter.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Decide whether the insertion needs a leading space given the character before the cursor.
    static func needsLeadingSpace(before: String?) -> Bool {
        guard let last = before?.last else { return false }
        if last.isWhitespace || last.isNewline { return false }
        if "([{\"'‘“/–—-".contains(last) { return false }
        return true
    }

    /// Full join: prefix a space when required by surrounding context.
    static func joined(_ text: String, textBeforeCursor: String?) -> String {
        needsLeadingSpace(before: textBeforeCursor) ? " " + text : text
    }

    private static let trailingActionPattern = try! NSRegularExpression(
        pattern: #"[\s,]*\b(press enter|hit enter|press return|send it|send message)\b[\s.!?]*$"#,
        options: [.caseInsensitive]
    )

    /// Detect a trailing spoken action ("… press enter"). Returns the text with the
    /// phrase stripped plus the keystroke name, or (text, nil) when absent.
    static func extractTrailingAction(_ text: String) -> (text: String, keystroke: String?) {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = trailingActionPattern.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text)
        else { return (text, nil) }
        let stripped = String(text[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return (text, nil) } // bare "press enter" is content, not a command
        return (stripped, "enter")
    }
}
