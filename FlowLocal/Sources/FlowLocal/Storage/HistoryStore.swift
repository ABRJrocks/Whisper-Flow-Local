import Foundation

/// Records completed sessions into the transcripts table.
enum HistoryStore {
    static func record(
        sessionType: String,
        language: String,
        appName: String?,
        bundleID: String?,
        raw: String,
        ruleText: String?,
        finalText: String,
        selectedTextBefore: String? = nil,
        commandInstruction: String? = nil,
        asrEngine: String?,
        llmModel: String?,
        audioDurationMs: Int?,
        asrLatencyMs: Int?,
        refinementLatencyMs: Int?,
        insertionStatus: String,
        errorCode: String? = nil,
        isSensitive: Bool = false,
        audioPath: String? = nil
    ) {
        guard Prefs.historyEnabled else { return }
        var record = TranscriptRecord(
            id: nil,
            createdAt: Date(),
            sessionType: sessionType,
            language: language,
            appName: appName,
            bundleId: bundleID,
            rawText: isSensitive ? "" : raw,
            ruleProcessedText: isSensitive ? nil : ruleText,
            finalText: isSensitive ? "•••" : finalText,
            selectedTextBefore: selectedTextBefore,
            commandInstruction: commandInstruction,
            asrEngine: asrEngine,
            llmModel: llmModel,
            audioDurationMs: audioDurationMs,
            asrLatencyMs: asrLatencyMs,
            refinementLatencyMs: refinementLatencyMs,
            insertionStatus: insertionStatus,
            errorCode: errorCode,
            isSensitive: isSensitive,
            audioPath: audioPath
        )
        do {
            try AppDatabase.shared.queue.write { db in
                try record.insert(db)
            }
        } catch {
            log.error("History insert failed: \(error.localizedDescription)")
        }
    }
}
