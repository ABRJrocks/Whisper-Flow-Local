import Foundation
import GRDB
import Testing

@testable import FlowLocal

/// Storage-layer checks for the Scratchpad: note CRUD, pinning, and version rows.
struct ScratchpadStoreTests {
    @Test func noteRoundTrip() throws {
        let database = try AppDatabase(inMemory: true)
        var note = NoteRecord.new()
        note.content = "hello\nworld"
        note.title = "hello"
        try database.queue.write { db in try note.save(db) }

        let fetched = try database.queue.read { db in try NoteRecord.fetchAll(db) }
        #expect(fetched.count == 1)
        #expect(fetched[0].content == "hello\nworld")
        #expect(fetched[0].title == "hello")
        #expect(fetched[0].pinned == false)
    }

    @Test func updateAndPin() throws {
        let database = try AppDatabase(inMemory: true)
        var note = NoteRecord.new()
        try database.queue.write { db in try note.save(db) }

        note.content = "edited"
        note.pinned = true
        note.updatedAt = Date()
        try database.queue.write { db in try note.save(db) }

        let fetched = try database.queue.read { db in try NoteRecord.fetchAll(db) }
        #expect(fetched.count == 1)
        #expect(fetched[0].content == "edited")
        #expect(fetched[0].pinned == true)
    }

    @Test func versionInsertAndCascadeDelete() throws {
        let database = try AppDatabase(inMemory: true)
        let note = NoteRecord.new()
        try database.queue.write { db in
            try note.save(db)
            try db.execute(
                sql: "INSERT INTO note_versions (note_id, content, created_at) VALUES (?, ?, ?)",
                arguments: [note.id, "v1", Date()]
            )
        }
        let versions = try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_versions") ?? -1
        }
        #expect(versions == 1)

        _ = try database.queue.write { db in try note.delete(db) }
        let after = try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_versions") ?? -1
        }
        #expect(after == 0)
    }
}
