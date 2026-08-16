import Foundation
import GRDB

struct TranscriptRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "transcripts"

    var id: Int64?
    var createdAt: Date
    var sessionType: String        // "dictation" | "command"
    var language: String
    var appName: String?
    var bundleId: String?
    var rawText: String
    var ruleProcessedText: String?
    var finalText: String
    var selectedTextBefore: String?
    var commandInstruction: String?
    var asrEngine: String?
    var llmModel: String?
    var audioDurationMs: Int?
    var asrLatencyMs: Int?
    var refinementLatencyMs: Int?
    var insertionStatus: String?   // "pasted" | "copied" | "failed"
    var errorCode: String?
    var isSensitive: Bool
    var audioPath: String?         // retained recording for failed dictations (recovery)

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case sessionType = "session_type"
        case language
        case appName = "app_name"
        case bundleId = "bundle_id"
        case rawText = "raw_text"
        case ruleProcessedText = "rule_processed_text"
        case finalText = "final_text"
        case selectedTextBefore = "selected_text_before"
        case commandInstruction = "command_instruction"
        case asrEngine = "asr_engine"
        case llmModel = "llm_model"
        case audioDurationMs = "audio_duration_ms"
        case asrLatencyMs = "asr_latency_ms"
        case refinementLatencyMs = "refinement_latency_ms"
        case insertionStatus = "insertion_status"
        case errorCode = "error_code"
        case isSensitive = "is_sensitive"
        case audioPath = "audio_path"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct DictionaryEntryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "dictionary_entries"

    var id: String
    var language: String?
    var spokenForm: String?
    var writtenForm: String
    var type: String               // vocabulary | replacement | spokenAlias | protectedTerm
    var caseSensitive: Bool
    var wholeWord: Bool
    var priority: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, language, type, priority
        case spokenForm = "spoken_form"
        case writtenForm = "written_form"
        case caseSensitive = "case_sensitive"
        case wholeWord = "whole_word"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func new(spoken: String?, written: String, type: String = "replacement") -> DictionaryEntryRecord {
        DictionaryEntryRecord(
            id: UUID().uuidString, language: nil, spokenForm: spoken, writtenForm: written,
            type: type, caseSensitive: false, wholeWord: true, priority: 0,
            createdAt: Date(), updatedAt: Date()
        )
    }
}

struct SnippetRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "snippets"

    var id: String
    var trigger: String
    var aliasesJson: String
    var expansion: String
    var category: String?
    var isSensitive: Bool
    var allowInline: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, trigger, expansion, category
        case aliasesJson = "aliases_json"
        case isSensitive = "is_sensitive"
        case allowInline = "allow_inline"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var aliases: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(aliasesJson.utf8))) ?? []
    }

    static func new(trigger: String, expansion: String) -> SnippetRecord {
        SnippetRecord(
            id: UUID().uuidString, trigger: trigger, aliasesJson: "[]", expansion: expansion,
            category: nil, isSensitive: false, allowInline: false, createdAt: Date(), updatedAt: Date()
        )
    }
}

struct StyleRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "styles"

    var id: String
    var name: String
    var category: String           // personal_message | work_message | email | documents | coding | terminal | ai_chat | other
    var formality: Double
    var concision: Double
    var emojiAllowed: Bool
    var omitFinalPeriodShort: Bool
    var customInstructions: String

    enum CodingKeys: String, CodingKey {
        case id, name, category, formality, concision
        case emojiAllowed = "emoji_allowed"
        case omitFinalPeriodShort = "omit_final_period_short"
        case customInstructions = "custom_instructions"
    }

    static let defaults: [StyleRecord] = [
        StyleRecord(id: "personal", name: "Personal Messages", category: "personal_message",
                    formality: 0.2, concision: 0.6, emojiAllowed: true, omitFinalPeriodShort: true, customInstructions: ""),
        StyleRecord(id: "work", name: "Work Messages", category: "work_message",
                    formality: 0.5, concision: 0.7, emojiAllowed: false, omitFinalPeriodShort: true, customInstructions: ""),
        StyleRecord(id: "email", name: "Email", category: "email",
                    formality: 0.7, concision: 0.5, emojiAllowed: false, omitFinalPeriodShort: false, customInstructions: ""),
        StyleRecord(id: "documents", name: "Documents", category: "documents",
                    formality: 0.6, concision: 0.4, emojiAllowed: false, omitFinalPeriodShort: false, customInstructions: ""),
        StyleRecord(id: "coding", name: "Coding", category: "coding",
                    formality: 0.4, concision: 0.8, emojiAllowed: false, omitFinalPeriodShort: true,
                    customInstructions: "Preserve identifiers, casing, and technical terms exactly."),
        StyleRecord(id: "other", name: "Other", category: "other",
                    formality: 0.5, concision: 0.5, emojiAllowed: false, omitFinalPeriodShort: false, customInstructions: ""),
    ]
}

struct NoteRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "notes"

    var id: String
    var title: String
    var content: String
    var pinned: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, content, pinned
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func new() -> NoteRecord {
        NoteRecord(id: UUID().uuidString, title: "", content: "", pinned: false, createdAt: Date(), updatedAt: Date())
    }
}
