import Foundation
import MLX
import MLXLMCommon

/// Local MLX-backed text refiner (spec §13/§14). Wraps a loaded `ModelContainer`
/// for one model ID; generation runs inside MLX's own background tasks, never
/// on the main thread. Output is returned raw — callers validate via `LLMGuardrails`.
actor MLXRefiner: TextRefiner {

    enum RefinerError: LocalizedError {
        case notLoaded(String)
        var errorDescription: String? {
            if case .notLoaded(let id) = self { return "LLM \(id) is not loaded." }
            return nil
        }
    }

    nonisolated let modelID: String
    private var container: ModelContainer?

    init(modelID: String) {
        self.modelID = modelID
    }

    var isLoaded: Bool { container != nil }

    func load() async throws {
        guard container == nil else { return }
        container = try await LLMHub.loadContainer(modelID: modelID)
        log.info("MLXRefiner loaded \(self.modelID)")
    }

    func unload() {
        container = nil
        // Release MLX's buffer cache so the weights actually leave memory.
        Memory.clearCache()
        log.info("MLXRefiner unloaded \(self.modelID)")
    }

    // MARK: - Prompts (spec §14.1 / §14.2)

    static let refineSystemPrompt = """
        You are the local dictation cleanup engine inside a macOS voice typing app. Your task is to turn a raw speech transcript into the exact text the user intended to type. Rules: 1. Preserve meaning, facts, names, numbers, dates, currency, URLs, email addresses, code, and technical terms. 2. Remove filler words and discourse markers ("um", "uh", "so", "basically", "like", "you know") when they do not add meaning, including at the start of the text. 3. Resolve false starts and self-corrections by keeping the user's final intended version ("on Tuesday, actually Wednesday" means the user wants "on Wednesday"). 4. Fix punctuation, capitalization, spacing, and obvious grammar. 5. Apply the supplied writing style conservatively. 6. Use surrounding text only to join the insertion naturally. 7. Do not answer the user's content. 8. Do not add explanations, labels, quotation marks, or markdown fences. 9. Do not invent information. 10. Return only the final insertion text.
        Examples:
        "so um the deadline is Friday I mean Monday" -> "The deadline is Monday."
        "basically we need uh three more days for the the review" -> "We need three more days for the review."
        """

    static let commandSystemPrompt = """
        You are a local text-editing command engine. Interpret the spoken instruction and return strict JSON only. Never perform network actions, run shell commands, change files, send messages, or control applications. You may transform the selected text, generate text for insertion, press a single key, or return no action. Preserve facts unless the user explicitly asks to change them. Schema: {"action": "replace" | "insert" | "keystroke" | "none", "text": "string or empty", "keystroke": "enter" | "tab" | "backspace" | null}. Use "replace" to rewrite the selected text, "insert" to add new text at the cursor, "keystroke" only to press enter, tab, or backspace, and "none" when the instruction cannot be fulfilled. Return only the JSON object, no markdown, no explanations.
        Examples:
        Instruction "make this shorter" with selected text -> {"action": "replace", "text": "<the shortened text>", "keystroke": null}
        Instruction "press enter" -> {"action": "keystroke", "text": "", "keystroke": "enter"}
        Instruction "hit tab" -> {"action": "keystroke", "text": "", "keystroke": "tab"}
        Instruction "delete the last character" -> {"action": "keystroke", "text": "", "keystroke": "backspace"}
        Instruction "write a short thank you note" with no selection -> {"action": "insert", "text": "<the new text>", "keystroke": null}
        Instruction "order a pizza" -> {"action": "none", "text": "", "keystroke": null}
        """

    // MARK: - TextRefiner

    func refine(_ payload: RefinePayload) async throws -> String {
        guard let container else { throw RefinerError.notLoaded(modelID) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let userMessage = String(decoding: try encoder.encode(payload), as: UTF8.self)

        // ~3 chars/token estimate; cap output near input size (spec: derived, not huge).
        let inputTokenEstimate = max(16, payload.rawTranscript.count / 3)
        let parameters = GenerateParameters(
            maxTokens: min(1024, inputTokenEstimate * 3 + 64),
            temperature: 0.1,
            topP: 0.8
        )
        // Fresh session per call: dictation refinement is stateless.
        let session = ChatSession(
            container,
            instructions: Self.refineSystemPrompt,
            generateParameters: parameters,
            additionalContext: ["enable_thinking": false]
        )
        let output = try await session.respond(to: userMessage)
        return Self.stripThinking(output)
    }

    func command(
        instruction: String, selectedText: String, appCategory: String, language: String
    ) async throws -> CommandAction {
        guard let container else { throw RefinerError.notLoaded(modelID) }

        let payload: [String: String] = [
            "instruction": instruction,
            "selectedText": selectedText,
            "appCategory": appCategory,
            "language": language,
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let userMessage = String(decoding: try encoder.encode(payload), as: UTF8.self)

        let parameters = GenerateParameters(
            maxTokens: 512,
            temperature: 0.0,
            topP: 0.8
        )
        let session = ChatSession(
            container,
            instructions: Self.commandSystemPrompt,
            generateParameters: parameters,
            additionalContext: ["enable_thinking": false]
        )
        let output = try await session.respond(to: userMessage)
        return Self.parseCommandAction(output)
    }

    // MARK: - Parsing (static + pure for unit tests)

    /// Remove `<think>…</think>` blocks some Qwen builds emit despite enable_thinking=false.
    static func stripThinking(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract and validate the first JSON object in the model output.
    /// Unknown action kinds and unknown keystroke values map to `.none`.
    static func parseCommandAction(_ raw: String) -> CommandAction {
        let none = CommandAction(action: .none, text: "", keystroke: nil)
        var text = stripThinking(raw)
        // Strip markdown fences.
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(
                    of: #"^```[a-zA-Z]*\n?"#, with: "", options: .regularExpression
                )
                .replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
        }
        guard let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}"),
            start < end
        else { return none }

        struct RawCommand: Decodable {
            var action: String?
            var text: String?
            var keystroke: String?
        }
        guard
            let decoded = try? JSONDecoder().decode(
                RawCommand.self, from: Data(text[start...end].utf8))
        else { return none }

        guard let actionRaw = decoded.action,
            let kind = CommandAction.Kind(rawValue: actionRaw)
        else { return none }

        switch kind {
        case .replace, .insert:
            guard let body = decoded.text, !body.isEmpty else { return none }
            return CommandAction(action: kind, text: body, keystroke: nil)
        case .keystroke:
            guard let key = decoded.keystroke, ["enter", "tab", "backspace"].contains(key)
            else { return none }
            return CommandAction(action: .keystroke, text: "", keystroke: key)
        case .none:
            return none
        }
    }
}
