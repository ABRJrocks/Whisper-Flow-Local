import AppKit
import ApplicationServices
import Foundation
import GRDB

/// Auto-learning dictionary: after a paste, re-read the target field ~20 s later and
/// word-diff what we inserted against what's there now. A substitution seen twice
/// becomes a dictionary replacement — the same store the deterministic pipeline uses.
@MainActor
enum CorrectionLearner {
    static let checkDelay: TimeInterval = 20
    static let promoteThreshold = 2

    static func observeAfterPaste(inserted: String) {
        guard Prefs.autoLearnEnabled, inserted.count >= 3 else { return }
        guard let element = FocusReader.focusedElement() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + checkDelay) {
            check(inserted: inserted, element: element)
        }
    }

    private static func check(inserted: String, element: AXUIElement) {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let fieldText = valueRef as? String, !fieldText.isEmpty
        else { return }
        // Only diff when the field is mostly our paste — otherwise locating the edited
        // region is guesswork. ponytail: anchored region search if this proves too narrow.
        guard fieldText.count <= inserted.count * 3 + 200 else { return }

        for (spoken, written) in WordDiff.substitutions(from: inserted, to: fieldText) {
            record(spoken: spoken, written: written)
        }
    }

    /// Tally a correction; promote to a real dictionary replacement at the threshold.
    static func record(spoken: String, written: String, database: AppDatabase = .shared) {
        do {
            try database.queue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO learned_corrections (spoken, written, count, updated_at)
                    VALUES (?, ?, 1, ?)
                    ON CONFLICT(spoken, written) DO UPDATE SET count = count + 1, updated_at = ?
                    """,
                    arguments: [spoken, written, Date(), Date()]
                )
                let count = try Int.fetchOne(
                    db, sql: "SELECT count FROM learned_corrections WHERE spoken = ? AND written = ?",
                    arguments: [spoken, written]
                ) ?? 0
                guard count >= promoteThreshold else { return }

                let exists = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM dictionary_entries WHERE spoken_form = ? COLLATE NOCASE",
                    arguments: [spoken]
                ) ?? 0
                if exists == 0 {
                    let entry = DictionaryEntryRecord.new(spoken: spoken, written: written)
                    try entry.save(db)
                    log.info("Auto-learned dictionary entry: \(spoken, privacy: .private) → \(written, privacy: .private)")
                }
                try db.execute(
                    sql: "DELETE FROM learned_corrections WHERE spoken = ? AND written = ?",
                    arguments: [spoken, written]
                )
            }
        } catch {
            log.warning("Correction tally failed: \(error.localizedDescription)")
        }
    }
}

/// Word-level LCS diff extracting clean 1:1 substitutions ("Cursor" → "Kursor").
enum WordDiff {
    static func substitutions(from old: String, to new: String) -> [(String, String)] {
        let oldWords = tokenize(old)
        let newWords = tokenize(new)
        guard !oldWords.isEmpty, !newWords.isEmpty,
              oldWords.count <= 400, newWords.count <= 400 // LCS is O(n·m)
        else { return [] }

        // Standard LCS table on lowercased words.
        let a = oldWords.map { $0.lowercased() }
        let b = newWords.map { $0.lowercased() }
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        // Walk the table; a run of exactly one deletion next to exactly one insertion is a substitution.
        var result: [(String, String)] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            var deleted: [String] = []
            var insertedWords: [String] = []
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, a[i] == b[j] { break } // mismatch run over
                if i < a.count, j >= b.count || lcs[i + 1][j] >= lcs[i][j + 1] {
                    deleted.append(oldWords[i]); i += 1
                } else {
                    insertedWords.append(newWords[j]); j += 1
                }
            }
            if deleted.count == 1, insertedWords.count == 1,
               isLearnable(old: deleted[0], new: insertedWords[0])
            {
                result.append((deleted[0], insertedWords[0]))
            }
        }
        return result
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map {
            String($0).trimmingCharacters(in: CharacterSet.punctuationCharacters)
        }.filter { !$0.isEmpty }
    }

    /// Worth learning: real word, actually different (not just case/punctuation), no digits-only noise.
    private static func isLearnable(old: String, new: String) -> Bool {
        guard old.count >= 3, !new.isEmpty, new.count <= 60 else { return false }
        guard old.lowercased() != new.lowercased() else { return false }
        guard old.rangeOfCharacter(from: .letters) != nil, new.rangeOfCharacter(from: .letters) != nil else { return false }
        return true
    }
}
