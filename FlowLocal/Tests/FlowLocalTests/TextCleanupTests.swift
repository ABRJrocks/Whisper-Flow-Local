import Testing
@testable import FlowLocal

@Suite struct TextCleanupTests {
    @Test func trimsAndCapitalizes() {
        #expect(TextCleanup.clean("  hello world  ") == "Hello world")
        #expect(TextCleanup.clean("Already fine.") == "Already fine.")
        #expect(TextCleanup.clean("") == "")
        #expect(TextCleanup.clean("   ") == "")
    }

    @Test func collapsesDoubleSpaces() {
        #expect(TextCleanup.clean("a  b   c") == "A b c")
    }

    @Test func preservesNonLatin() {
        #expect(TextCleanup.clean("یہ ایک ٹیسٹ ہے") == "یہ ایک ٹیسٹ ہے")
    }

    @Test func leadingSpaceRules() {
        #expect(TextCleanup.needsLeadingSpace(before: "Please send") == true)
        #expect(TextCleanup.needsLeadingSpace(before: "Please send ") == false)
        #expect(TextCleanup.needsLeadingSpace(before: nil) == false)
        #expect(TextCleanup.needsLeadingSpace(before: "") == false)
        #expect(TextCleanup.needsLeadingSpace(before: "line1\n") == false)
        #expect(TextCleanup.needsLeadingSpace(before: "(") == false)
        #expect(TextCleanup.needsLeadingSpace(before: "\"") == false)
    }

    @Test func joining() {
        #expect(TextCleanup.joined("the report", textBeforeCursor: "Please send") == " the report")
        #expect(TextCleanup.joined("The report", textBeforeCursor: "Done. ") == "The report")
    }
}
