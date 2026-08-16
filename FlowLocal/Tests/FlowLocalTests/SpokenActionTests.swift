import Testing

@testable import FlowLocal

struct SpokenActionTests {
    @Test func stripsTrailingPressEnter() {
        let (text, key) = TextCleanup.extractTrailingAction("Sounds good, see you then. Press enter")
        #expect(text == "Sounds good, see you then.")
        #expect(key == "enter")
    }

    @Test func stripsSendItWithComma() {
        let (text, key) = TextCleanup.extractTrailingAction("On my way, send it")
        #expect(text == "On my way")
        #expect(key == "enter")
    }

    @Test func bareCommandIsContent() {
        let (text, key) = TextCleanup.extractTrailingAction("Press enter")
        #expect(text == "Press enter")
        #expect(key == nil)
    }

    @Test func midSentenceMentionUntouched() {
        let (text, key) = TextCleanup.extractTrailingAction("You should press enter to submit the form")
        #expect(text == "You should press enter to submit the form")
        #expect(key == nil)
    }

    @Test func noCommandPassesThrough() {
        let (text, key) = TextCleanup.extractTrailingAction("Just a normal sentence.")
        #expect(text == "Just a normal sentence.")
        #expect(key == nil)
    }
}
