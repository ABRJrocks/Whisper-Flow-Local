import Foundation
import GRDB

/// All durable local storage. One SQLite file under Application Support.
final class AppDatabase: Sendable {
    static let shared = try! AppDatabase()

    let queue: DatabaseQueue

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlowLocal", isDirectory: true)
    }

    private init() throws {
        let dbDirectory = Self.supportDirectory.appendingPathComponent("Database", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: dbDirectory.appendingPathComponent("flowlocal.sqlite").path)
        try migrator.migrate(queue)
    }

    /// In-memory database for tests.
    init(inMemory: Bool) throws {
        queue = try DatabaseQueue()
        try migrator.migrate(queue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "transcripts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("created_at", .datetime).notNull().indexed()
                t.column("session_type", .text).notNull().defaults(to: "dictation")
                t.column("language", .text).notNull().defaults(to: "en")
                t.column("app_name", .text)
                t.column("bundle_id", .text)
                t.column("raw_text", .text).notNull()
                t.column("rule_processed_text", .text)
                t.column("final_text", .text).notNull()
                t.column("selected_text_before", .text)
                t.column("command_instruction", .text)
                t.column("asr_engine", .text)
                t.column("llm_model", .text)
                t.column("audio_duration_ms", .integer)
                t.column("asr_latency_ms", .integer)
                t.column("refinement_latency_ms", .integer)
                t.column("insertion_status", .text)
                t.column("error_code", .text)
                t.column("is_sensitive", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "dictionary_entries") { t in
                t.column("id", .text).primaryKey()
                t.column("language", .text)
                t.column("spoken_form", .text)
                t.column("written_form", .text).notNull()
                t.column("type", .text).notNull().defaults(to: "replacement")
                t.column("case_sensitive", .boolean).notNull().defaults(to: false)
                t.column("whole_word", .boolean).notNull().defaults(to: true)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "snippets") { t in
                t.column("id", .text).primaryKey()
                t.column("trigger", .text).notNull()
                t.column("aliases_json", .text).notNull().defaults(to: "[]")
                t.column("expansion", .text).notNull()
                t.column("category", .text)
                t.column("is_sensitive", .boolean).notNull().defaults(to: false)
                t.column("allow_inline", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "styles") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("category", .text).notNull()
                t.column("formality", .double).notNull().defaults(to: 0.5)
                t.column("concision", .double).notNull().defaults(to: 0.5)
                t.column("emoji_allowed", .boolean).notNull().defaults(to: false)
                t.column("omit_final_period_short", .boolean).notNull().defaults(to: false)
                t.column("custom_instructions", .text).notNull().defaults(to: "")
            }
            try db.create(table: "notes") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull().indexed()
            }
            try db.create(table: "note_versions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("note_id", .text).notNull().indexed()
                    .references("notes", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            // Dictation recovery: path to retained audio for failed transcriptions.
            try db.alter(table: "transcripts") { t in
                t.add(column: "audio_path", .text)
            }
            // Auto-learning dictionary: tally of observed user corrections.
            try db.create(table: "learned_corrections") { t in
                t.column("spoken", .text).notNull()
                t.column("written", .text).notNull()
                t.column("count", .integer).notNull().defaults(to: 1)
                t.column("updated_at", .datetime).notNull()
                t.primaryKey(["spoken", "written"])
            }
        }
        return migrator
    }
}

// MARK: - Retention

enum RetentionService {
    /// Delete transcripts older than the configured retention window. Call at launch and daily.
    static func cleanUp(database: AppDatabase = .shared) {
        let days = Prefs.historyRetentionDays
        guard days > 0 else { return } // 0 = keep forever
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        do {
            try database.queue.write { db in
                try db.execute(sql: "DELETE FROM transcripts WHERE created_at < ?", arguments: [cutoff])
            }
        } catch {
            log.error("Retention cleanup failed: \(error.localizedDescription)")
        }
        // Recovery audio whose transcript row is gone (deleted or expired) is dead weight.
        let referenced = (try? database.queue.read { db in
            try String.fetchAll(db, sql: "SELECT audio_path FROM transcripts WHERE audio_path IS NOT NULL")
        }) ?? []
        RecoveryStore.cleanUpOrphans(referencedPaths: Set(referenced))
    }
}
