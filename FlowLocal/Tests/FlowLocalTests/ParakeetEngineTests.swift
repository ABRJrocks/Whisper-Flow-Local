import Foundation
import Testing

@testable import FlowLocal

@Suite struct ParakeetEngineTests {
    @Test func supportsPublishedEuropeanLanguages() async {
        let engine = ParakeetEngine()
        #expect(await engine.supports(locale: Locale(identifier: "en_US")))
        #expect(await engine.supports(locale: Locale(identifier: "de_DE")))
        #expect(await engine.supports(locale: Locale(identifier: "uk_UA")))
        #expect(!(await engine.supports(locale: Locale(identifier: "ja_JP"))))
        #expect(!(await engine.supports(locale: Locale(identifier: "zh_CN"))))
    }

    @Test func notReadyForUnsupportedLanguageEvenIfModelInstalled() async {
        let engine = ParakeetEngine()
        #expect(!(await engine.isReady(locale: Locale(identifier: "ja_JP"))))
    }
}
