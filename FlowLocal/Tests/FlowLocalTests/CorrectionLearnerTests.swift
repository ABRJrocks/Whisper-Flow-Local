import Foundation
import GRDB
import Testing

@testable import FlowLocal

struct WordDiffTests {
    @Test func singleSubstitution() {
        let subs = WordDiff.substitutions(
            from: "Meet me at the Cursor office tomorrow",
            to: "Meet me at the Kursor office tomorrow"
        )
        #expect(subs.count == 1)
        #expect(subs[0].0 == "Cursor")
        #expect(subs[0].1 == "Kursor")
    }

    @Test func caseOnlyChangeIgnored() {
        let subs = WordDiff.substitutions(from: "hello world", to: "hello World")
        #expect(subs.isEmpty)
    }

    @Test func identicalTextNoSubstitutions() {
        #expect(WordDiff.substitutions(from: "same text here", to: "same text here").isEmpty)
    }

    @Test func multiWordEditNotTreatedAsSubstitution() {
        // One word replaced by three — ambiguous, must not learn.
        let subs = WordDiff.substitutions(
            from: "send the report today",
            to: "send the quarterly financial summary today"
        )
        #expect(subs.isEmpty)
    }

    @Test func multipleIndependentSubstitutions() {
        let subs = WordDiff.substitutions(
            from: "email Jhon about the Parrakeet launch",
            to: "email John about the Parakeet launch"
        )
        #expect(subs.count == 2)
        #expect(subs.contains { $0.0 == "Jhon" && $0.1 == "John" })
        #expect(subs.contains { $0.0 == "Parrakeet" && $0.1 == "Parakeet" })
    }

    @Test func punctuationStrippedFromTokens() {
        let subs = WordDiff.substitutions(from: "call Symone.", to: "call Simone.")
        #expect(subs.count == 1)
        #expect(subs[0].0 == "Symone")
        #expect(subs[0].1 == "Simone")
    }
}

@MainActor
struct CorrectionLearnerStoreTests {
    @Test func promotesAfterThreshold() throws {
        let database = try AppDatabase(inMemory: true)

        CorrectionLearner.record(spoken: "Jhon", written: "John", database: database)
        var entries = try database.queue.read { db in try DictionaryEntryRecord.fetchAll(db) }
        #expect(entries.isEmpty) // one sighting is not enough

        CorrectionLearner.record(spoken: "Jhon", written: "John", database: database)
        entries = try database.queue.read { db in try DictionaryEntryRecord.fetchAll(db) }
        #expect(entries.count == 1)
        #expect(entries[0].spokenForm == "Jhon")
        #expect(entries[0].writtenForm == "John")

        // Tally row consumed on promotion.
        let tally = try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM learned_corrections") ?? -1
        }
        #expect(tally == 0)
    }

    @Test func noDuplicateEntryForKnownSpokenForm() throws {
        let database = try AppDatabase(inMemory: true)
        try database.queue.write { db in
            try DictionaryEntryRecord.new(spoken: "Jhon", written: "Jon").save(db)
        }
        CorrectionLearner.record(spoken: "Jhon", written: "John", database: database)
        CorrectionLearner.record(spoken: "Jhon", written: "John", database: database)
        let entries = try database.queue.read { db in try DictionaryEntryRecord.fetchAll(db) }
        #expect(entries.count == 1) // the user's manual entry wins
        #expect(entries[0].writtenForm == "Jon")
    }
}
