import Foundation

/// Deterministic self-correction handling (spec §13.4).
/// "Send it on Tuesday, actually Wednesday" -> "Send it on Wednesday"
/// "The price is five hundred, scratch that, six hundred dollars" -> "The price is six hundred dollars"
/// "Contact Umar, no, Umer Anjum" -> "Contact Umer Anjum"
/// Conservative: explicit markers only, never inside quotes/URLs/code, and only when the
/// corrected span can be aligned confidently. Otherwise the text is left untouched.
enum BacktrackProcessor {
    private static let markers = [
        "scratch that,", "scratch that", "no wait,", "no wait", "i mean,", "i mean",
        "actually,", "actually", "make that,", "make that", "no,",
    ]

    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "to", "of", "in", "on", "at", "for", "is", "it", "was",
    ]

    static func process(_ text: String) -> String {
        guard !containsProtectedContent(text) else { return text }
        var result = text
        for marker in markers {
            result = applyMarker(marker, to: result)
        }
        return result
    }

    private static func applyMarker(_ marker: String, to text: String) -> String {
        let lower = text.lowercased()
        // ", <marker> " — comma boundary avoids firing on sentence-initial "Actually".
        guard let markerRange = lower.range(of: ", " + marker + " ") else { return text }

        let before = text[..<markerRange.lowerBound]
        let after = text[markerRange.upperBound...]

        let sentenceStart = before.lastIndex(where: { ".!?\n".contains($0) })
            .map { before.index(after: $0) } ?? before.startIndex
        let clause = before[sentenceStart...]
        let clauseWords = clause.split(separator: " ").map(String.init)

        let correction = after.prefix(while: { !".!?,\n".contains($0) })
        let correctionWords = correction.split(separator: " ").map(String.init)
        guard !clauseWords.isEmpty, !correctionWords.isEmpty else { return text }

        // Anchor the corrected span: find a correction word (fuzzy) inside the clause.
        var dropStart: Int?
        outer: for (ci, cw) in correctionWords.enumerated() {
            let key = normalize(cw)
            if key.count < 3 || stopwords.contains(key) { continue }
            for bi in stride(from: clauseWords.count - 1, through: 0, by: -1) {
                if similar(normalize(clauseWords[bi]), key) {
                    let start = bi - ci
                    if start >= 0 {
                        dropStart = start
                        break outer
                    }
                }
            }
        }
        // No anchor: only substitute when the correction is short — a likely word swap.
        if dropStart == nil {
            if correctionWords.count <= 3 && correctionWords.count <= clauseWords.count {
                dropStart = clauseWords.count - correctionWords.count
            } else {
                return text
            }
        }
        guard let start = dropStart, start >= 0, start <= clauseWords.count else { return text }

        let keptClause = clauseWords[..<start].joined(separator: " ")
        let head = String(before[..<sentenceStart])
        let rebuilt = head + keptClause + (keptClause.isEmpty ? "" : " ") + String(after)
        return rebuilt.replacingOccurrences(of: "  ", with: " ")
    }

    private static func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    /// Exact match, or small edit distance for near-misses like "Umar" vs "Umer".
    private static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count > 3, b.count > 3, abs(a.count - b.count) <= 1 else { return false }
        return editDistance(a, b) <= 1
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        var previous = Array(0...bChars.count)
        for (i, ca) in aChars.enumerated() {
            var current = [i + 1]
            for (j, cb) in bChars.enumerated() {
                current.append(min(
                    previous[j] + (ca == cb ? 0 : 1),
                    previous[j + 1] + 1,
                    current[j] + 1
                ))
            }
            previous = current
        }
        return previous[bChars.count]
    }

    private static func containsProtectedContent(_ text: String) -> Bool {
        text.contains("\"") || text.contains("“") || text.contains("http") || text.contains("`")
    }
}
