import Foundation

struct ProcessedText: Sendable {
    let ruleText: String
    let finalText: String
    let llmUsed: Bool
    let refinementMs: Int
    let usedSensitiveSnippet: Bool
}

/// Raw ASR → deterministic rules → optional local LLM polish (spec §13.1).
struct ProcessingPipeline: Sendable {
    var refiner: (any TextRefiner)?

    func process(
        raw: String,
        language: String,
        appCategory: String,
        style: StyleRecord?,
        textBeforeCursor: String?,
        secureContext: Bool
    ) async -> ProcessedText {
        // 1. Deterministic stages
        var text = TextCleanup.clean(raw)
        text = SpokenPunctuation.process(text)

        let entries = (try? await AppDatabase.shared.queue.read { db in
            try DictionaryEntryRecord.fetchAll(db)
        }) ?? []
        text = DictionaryProcessor(entries: entries).process(text)

        text = BacktrackProcessor.process(text)

        let snippets = (try? await AppDatabase.shared.queue.read { db in
            try SnippetRecord.fetchAll(db)
        }) ?? []
        let (expanded, usedSensitive) = SnippetProcessor(snippets: snippets).process(text)
        text = expanded

        let ruleText = text

        // 2. LLM refinement, when warranted and available
        var finalText = ruleText
        var llmUsed = false
        var refinementMs = 0
        let level = Prefs.cleanupLevel
        if let refiner,
           Prefs.llmRefinementEnabled,
           !usedSensitive,
           RefinementDecider.shouldRefine(ruleText, level: level)
        {
            let protectedTerms = LLMGuardrails.protectedTokens(in: ruleText)
                + entries.filter { $0.type == "protectedTerm" }.map(\.writtenForm)
            let levelInstruction: String
            switch level {
            case "light": levelInstruction = "Only remove filler words and fix punctuation or casing. Never rephrase or reorder the speaker's words."
            case "heavy": levelInstruction = "Where the dictation is long or rambling, restructure it into clear sentences; use a list when the speaker enumerates items."
            default: levelInstruction = ""
            }
            let payload = RefinePayload(
                rawTranscript: ruleText,
                language: language,
                appCategory: appCategory,
                formality: style?.formality ?? 0.5,
                concision: style?.concision ?? 0.5,
                emojiAllowed: style?.emojiAllowed ?? false,
                customInstructions: [style?.customInstructions ?? "", levelInstruction]
                    .filter { !$0.isEmpty }.joined(separator: " "),
                textBeforeCursor: secureContext ? nil : textBeforeCursor,
                protectedTerms: protectedTerms
            )
            let start = Date()
            do {
                let output = try await withTimeout(seconds: 10) {
                    try await refiner.refine(payload)
                }
                if let validated = LLMGuardrails.validate(output: output, input: ruleText) {
                    finalText = validated
                    llmUsed = true
                }
            } catch {
                log.warning("LLM refinement skipped: \(error.localizedDescription)")
            }
            refinementMs = Int(Date().timeIntervalSince(start) * 1000)
        }

        // 3. Style: short messaging texts may drop the final period
        if let style, style.omitFinalPeriodShort {
            finalText = dropFinalPeriodIfShort(finalText)
        }

        return ProcessedText(
            ruleText: ruleText,
            finalText: finalText,
            llmUsed: llmUsed,
            refinementMs: refinementMs,
            usedSensitiveSnippet: usedSensitive
        )
    }

    private func dropFinalPeriodIfShort(_ text: String) -> String {
        guard text.hasSuffix("."), !text.hasSuffix(".."),
              text.count < 80,
              !text.dropLast().contains(where: { ".!?\n".contains($0) })
        else { return text }
        return String(text.dropLast())
    }
}

/// Skip the LLM for short, clean utterances (spec §13.6): saves time, battery, heat.
enum RefinementDecider {
    private static let fillerPattern = try! NSRegularExpression(
        pattern: #"\b(um+|uh+|erm+|you know|i mean|like,|sort of|kind of|basically)\b"#,
        options: [.caseInsensitive]
    )

    static func shouldRefine(_ text: String, level: String = "standard") -> Bool {
        let words = text.split(separator: " ").count
        if words < 4 { return false }
        if level == "heavy" { return true }
        let range = NSRange(text.startIndex..., in: text)
        let fillers = fillerPattern.numberOfMatches(in: text, range: range)
        if fillers > 0 { return true }
        if words > 40 { return true }             // long unstructured utterance
        if text.contains(" actually ") || text.lowercased().contains("scratch that") { return true }
        // Repeated adjacent words hint at disfluency: "the the report"
        let tokens = text.lowercased().split(separator: " ")
        for i in 1..<max(1, tokens.count) where tokens[i] == tokens[i - 1] { return true }
        return false
    }
}

func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
