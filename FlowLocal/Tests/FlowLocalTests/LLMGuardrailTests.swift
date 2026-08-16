import Testing

@testable import FlowLocal

@Suite struct LLMGuardrailTests {

    // MARK: - protectedTokens

    @Test func findsNumbersCurrencyEmailsURLs() {
        let tokens = LLMGuardrails.protectedTokens(
            in: "Pay $1,200.50 (15%) to bob@example.com via https://pay.example.com by 2026")
        #expect(tokens.contains("$1,200.50"))
        #expect(tokens.contains("15%"))
        #expect(tokens.contains("2026"))
        #expect(tokens.contains("bob@example.com"))
        #expect(tokens.contains(where: { $0.hasPrefix("https://pay.example.com") }))
    }

    @Test func plainTextHasNoProtectedTokens() {
        #expect(LLMGuardrails.protectedTokens(in: "hello there how are you").isEmpty)
    }

    // MARK: - validate

    @Test func acceptsCleanOutput() {
        #expect(LLMGuardrails.validate(output: "Hello world.", input: "uh hello world") == "Hello world.")
    }

    @Test func stripsFencesAndQuotes() {
        #expect(
            LLMGuardrails.validate(output: "```text\nHello world.\n```", input: "hello world")
                == "Hello world.")
        #expect(
            LLMGuardrails.validate(output: "\"Hello world.\"", input: "hello world")
                == "Hello world.")
    }

    @Test func rejectsEmptyOutput() {
        #expect(LLMGuardrails.validate(output: "   \n", input: "hello") == nil)
    }

    @Test func rejectsRunawayExpansion() {
        let input = "short input"
        let output = String(repeating: "blah ", count: 50)
        #expect(LLMGuardrails.validate(output: output, input: input) == nil)
        #expect(LLMGuardrails.validate(output: output, input: input, allowExpansion: true) != nil)
    }

    @Test func rejectsDroppedProtectedToken() {
        #expect(
            LLMGuardrails.validate(
                output: "Send the invoice to the client.",
                input: "send the invoice for $450 to the client") == nil)
        #expect(
            LLMGuardrails.validate(
                output: "Send the $450 invoice to the client.",
                input: "send the invoice for $450 to the client") != nil)
    }

    // MARK: - MLXRefiner.parseCommandAction

    @Test func parsesReplace() {
        let action = MLXRefiner.parseCommandAction(
            #"{"action": "replace", "text": "Shorter version.", "keystroke": null}"#)
        #expect(action.action == .replace)
        #expect(action.text == "Shorter version.")
        #expect(action.keystroke == nil)
    }

    @Test func parsesInsertInsideMarkdownFence() {
        let action = MLXRefiner.parseCommandAction(
            "```json\n{\"action\": \"insert\", \"text\": \"Hello\"}\n```")
        #expect(action.action == .insert)
        #expect(action.text == "Hello")
    }

    @Test func parsesKeystroke() {
        let action = MLXRefiner.parseCommandAction(
            #"{"action": "keystroke", "text": "", "keystroke": "enter"}"#)
        #expect(action.action == .keystroke)
        #expect(action.keystroke == "enter")
    }

    @Test func rejectsUnknownActionKind() {
        let action = MLXRefiner.parseCommandAction(
            #"{"action": "shell", "text": "rm -rf /"}"#)
        #expect(action.action == .none)
        #expect(action.text.isEmpty)
    }

    @Test func rejectsUnknownKeystroke() {
        let action = MLXRefiner.parseCommandAction(
            #"{"action": "keystroke", "text": "", "keystroke": "cmd+q"}"#)
        #expect(action.action == .none)
    }

    @Test func rejectsReplaceWithEmptyText() {
        let action = MLXRefiner.parseCommandAction(#"{"action": "replace", "text": ""}"#)
        #expect(action.action == .none)
    }

    @Test func rejectsNonJSONOutput() {
        #expect(MLXRefiner.parseCommandAction("Sure! I will replace the text.").action == .none)
        #expect(MLXRefiner.parseCommandAction("").action == .none)
    }

    @Test func parsesJSONSurroundedByProseAndThinking() {
        let action = MLXRefiner.parseCommandAction(
            "<think>user wants caps</think>Here you go: {\"action\": \"replace\", \"text\": \"HELLO\"} hope that helps")
        #expect(action.action == .replace)
        #expect(action.text == "HELLO")
    }

    @Test func handlesNestedBracesInText() {
        let action = MLXRefiner.parseCommandAction(
            #"{"action": "insert", "text": "func f() { return {} }"}"#)
        #expect(action.action == .insert)
        #expect(action.text == "func f() { return {} }")
    }

    // MARK: - MLXRefiner.stripThinking

    @Test func stripsThinkBlocks() {
        #expect(MLXRefiner.stripThinking("<think>\nreasoning\n</think>\nFinal text") == "Final text")
        #expect(MLXRefiner.stripThinking("No thinking here") == "No thinking here")
    }
}
