import Foundation

/// Picks the right engine for a language, honoring the user's forced choice,
/// installed state, and each engine's language coverage (spec §7).
final class ASRRouter: @unchecked Sendable {
    static let shared = ASRRouter()

    let apple = AppleSpeechEngine()
    let parakeet = ParakeetEngine()
    let whisper = WhisperEngine()

    var all: [any ASREngine] { [apple, parakeet, whisper] }

    /// Parakeet TDT v3's 25 published European languages (spec §7.2).
    static let parakeetLanguages: Set<String> = [
        "en", "de", "fr", "es", "it", "pt", "nl", "pl", "ru", "uk", "cs", "sk",
        "sv", "da", "no", "nb", "fi", "et", "lv", "lt", "hr", "sl", "ro", "hu", "el", "bg", "mt",
    ]

    func engine(for locale: Locale) async -> (any ASREngine)? {
        // Auto-detect: Whisper is the only engine that identifies the language itself.
        if locale.identifier == "auto" { return whisper }
        let lang = locale.language.languageCode?.identifier ?? "en"

        switch Prefs.preferredEngine {
        case "apple": return apple
        case "parakeet": return parakeet
        case "whisper": return whisper
        default: break // auto
        }

        if Self.parakeetLanguages.contains(lang), await parakeet.isReady(locale: locale) {
            return parakeet
        }
        if await apple.supports(locale: locale), await apple.isReady(locale: locale) {
            return apple
        }
        if await whisper.isReady(locale: locale) {
            return whisper
        }
        // Nothing installed for this language yet — fall back to anything that could work
        // after a prepare() (Apple can download on demand).
        if await apple.supports(locale: locale) {
            return apple
        }
        return nil
    }
}
