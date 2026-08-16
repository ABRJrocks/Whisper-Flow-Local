import Foundation
import Testing
@testable import FlowLocal

@Suite struct BacktrackTests {
    @Test func actuallyCorrection() {
        #expect(BacktrackProcessor.process("Send it on Tuesday, actually Wednesday.")
            == "Send it on Wednesday.")
    }

    @Test func scratchThat() {
        let out = BacktrackProcessor.process("The price is five hundred, scratch that, six hundred dollars.")
        #expect(out == "The price is six hundred dollars.")
    }

    @Test func sentenceInitialActuallyUntouched() {
        let text = "Actually, I think this is fine."
        #expect(BacktrackProcessor.process(text) == text)
    }

    @Test func quotedTextUntouched() {
        let text = "He said \"Tuesday, actually Wednesday\" yesterday."
        #expect(BacktrackProcessor.process(text) == text)
    }

    @Test func fuzzyNameCorrection() {
        #expect(BacktrackProcessor.process("Contact Umar, no, Umer Anjum.")
            == "Contact Umer Anjum.")
    }

    @Test func unrelatedClauseKept() {
        // No shared word and long clause -> too risky, leave alone.
        let text = "We shipped the entire migration pipeline last night, actually the rollback tooling needs work."
        #expect(BacktrackProcessor.process(text) == text)
    }
}

@Suite struct DictionaryProcessorTests {
    private func entry(_ spoken: String, _ written: String, wholeWord: Bool = true, caseSensitive: Bool = false, priority: Int = 0) -> DictionaryEntryRecord {
        var e = DictionaryEntryRecord.new(spoken: spoken, written: written)
        e.wholeWord = wholeWord
        e.caseSensitive = caseSensitive
        e.priority = priority
        return e
    }

    @Test func basicReplacement() {
        let p = DictionaryProcessor(entries: [entry("dev entities", "Dev Entities")])
        #expect(p.process("email dev entities today") == "email Dev Entities today")
    }

    @Test func wholeWordBoundary() {
        let p = DictionaryProcessor(entries: [entry("cat", "CAT")])
        #expect(p.process("the cat concatenated") == "the CAT concatenated")
    }

    @Test func longestMatchFirst() {
        let p = DictionaryProcessor(entries: [
            entry("post", "POST"),
            entry("postgres ql", "PostgreSQL"),
        ])
        #expect(p.process("use postgres ql now") == "use PostgreSQL now")
    }

    @Test func caseSensitiveRespected() {
        let p = DictionaryProcessor(entries: [entry("zca", "ZCA", caseSensitive: true)])
        #expect(p.process("the ZCA zca") == "the ZCA ZCA")
    }

    @Test func regexCharactersSafe() {
        let p = DictionaryProcessor(entries: [entry("c plus plus", "C++")])
        #expect(p.process("i like c plus plus a lot") == "i like C++ a lot")
    }

    @Test func urduPreserved() {
        let p = DictionaryProcessor(entries: [entry("salaam", "سلام")])
        #expect(p.process("say salaam please") == "say سلام please")
    }
}

@Suite struct SnippetTests {
    private func snippet(_ trigger: String, _ expansion: String, inline: Bool = false) -> SnippetRecord {
        var s = SnippetRecord.new(trigger: trigger, expansion: expansion)
        s.allowInline = inline
        return s
    }

    @Test func fullMatchExpansion() {
        let p = SnippetProcessor(snippets: [snippet("my meeting link", "https://calendly.com/example/30min")])
        let (out, sensitive) = p.process("My meeting link.")
        #expect(out == "https://calendly.com/example/30min")
        #expect(!sensitive)
    }

    @Test func noAccidentalInlineExpansion() {
        let p = SnippetProcessor(snippets: [snippet("my meeting link", "https://cal.example")])
        let (out, _) = p.process("I will send you my meeting link tomorrow.")
        #expect(out == "I will send you my meeting link tomorrow.")
    }

    @Test func inlineWhenAllowed() {
        let p = SnippetProcessor(snippets: [snippet("my address", "12 Example Road", inline: true)])
        let (out, _) = p.process("Ship it to my address please.")
        #expect(out == "Ship it to 12 Example Road please.")
    }

    @Test func placeholders() {
        let p = SnippetProcessor(snippets: [])
        let out = p.expandPlaceholders("line1{{newline}}line2")
        #expect(out == "line1\nline2")
    }
}

@Suite struct SpokenPunctuationTests {
    @Test func newParagraph() {
        #expect(SpokenPunctuation.process("first part new paragraph second part")
            == "first part\n\nsecond part")
    }

    @Test func questionMark() {
        let out = SpokenPunctuation.process("are you coming question mark")
        #expect(out == "are you coming?")
    }
}

@Suite struct RefinementDeciderTests {
    @Test func shortCleanSkips() {
        #expect(!RefinementDecider.shouldRefine("Send the report."))
    }

    @Test func fillersTrigger() {
        #expect(RefinementDecider.shouldRefine("So um I think we should you know ship it"))
    }

    @Test func repeatedWordTriggers() {
        #expect(RefinementDecider.shouldRefine("send the the report to finance"))
    }
}

@Suite struct GuardrailTests {
    @Test func protectedTokensFound() {
        let tokens = LLMGuardrails.protectedTokens(in: "Pay $1,250 to ali@dev.pk by March 3")
        #expect(tokens.contains("$1,250"))
        #expect(tokens.contains("ali@dev.pk"))
    }

    @Test func rejectsDroppedNumber() {
        let out = LLMGuardrails.validate(output: "Pay the amount by March", input: "Pay $500 by March 3")
        #expect(out == nil)
    }

    @Test func rejectsHugeExpansion() {
        let input = "short text"
        let output = String(repeating: "word ", count: 100)
        #expect(LLMGuardrails.validate(output: output, input: input) == nil)
    }

    @Test func stripsFencesAndQuotes() {
        let out = LLMGuardrails.validate(output: "```\nHello world\n```", input: "hello world umm")
        #expect(out == "Hello world")
    }
}
