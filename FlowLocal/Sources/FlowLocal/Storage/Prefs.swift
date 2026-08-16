import Foundation

/// The one language list — menu bar, General settings, and Model Center all share it.
enum AppLanguages {
    static let all: [(id: String, name: String)] = [
        ("auto", "Auto-detect (Whisper)"),
        ("en_US", "English (US)"),
        ("en_GB", "English (UK)"),
        ("ur_PK", "Urdu (Pakistan)"),
        ("ar_SA", "Arabic (Saudi Arabia)"),
        ("hi_IN", "Hindi (India)"),
        ("de_DE", "German"),
        ("fr_FR", "French"),
        ("es_ES", "Spanish"),
        ("it_IT", "Italian"),
        ("pt_BR", "Portuguese (Brazil)"),
    ]

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? id
    }
}

/// Lightweight preferences in UserDefaults (user content lives in SQLite, per spec §20.1).
enum Prefs {
    private static var d: UserDefaults { .standard }

    static var firstRunCompleted: Bool {
        get { d.bool(forKey: "firstRunCompleted") }
        set { d.set(newValue, forKey: "firstRunCompleted") }
    }

    /// BCP-47-ish locale identifier used for dictation.
    static var languageID: String {
        get { d.string(forKey: "languageID") ?? "en_US" }
        set { d.set(newValue, forKey: "languageID") }
    }

    /// "auto" | "apple" | "parakeet" | "whisper"
    static var preferredEngine: String {
        get { d.string(forKey: "preferredEngine") ?? "auto" }
        set { d.set(newValue, forKey: "preferredEngine") }
    }

    static var llmRefinementEnabled: Bool {
        get { d.object(forKey: "llmRefinementEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "llmRefinementEnabled") }
    }

    static var historyEnabled: Bool {
        get { d.object(forKey: "historyEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "historyEnabled") }
    }

    /// 0 = keep forever; otherwise days.
    static var historyRetentionDays: Int {
        get { d.object(forKey: "historyRetentionDays") as? Int ?? 30 }
        set { d.set(newValue, forKey: "historyRetentionDays") }
    }

    static var contextAwarenessEnabled: Bool {
        get { d.object(forKey: "contextAwarenessEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "contextAwarenessEnabled") }
    }

    static var showPartialTranscript: Bool {
        get { d.object(forKey: "showPartialTranscript") as? Bool ?? true }
        set { d.set(newValue, forKey: "showPartialTranscript") }
    }

    static var minimumPressMs: Int {
        get { d.object(forKey: "minimumPressMs") as? Int ?? 300 }
        set { d.set(newValue, forKey: "minimumPressMs") }
    }

    /// Hands-free: stop after this many seconds of silence. 0 disables.
    static var silenceTimeoutSeconds: Double {
        get { d.object(forKey: "silenceTimeoutSeconds") as? Double ?? 0 }
        set { d.set(newValue, forKey: "silenceTimeoutSeconds") }
    }

    static var sessionLimitMinutes: Int {
        get { d.object(forKey: "sessionLimitMinutes") as? Int ?? 20 }
        set { d.set(newValue, forKey: "sessionLimitMinutes") }
    }

    static var soundsEnabled: Bool {
        get { d.object(forKey: "soundsEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "soundsEnabled") }
    }

    /// Local LLM model repo ID for refinement; empty = not installed/selected.
    static var llmModelID: String {
        get { d.string(forKey: "llmModelID") ?? "" }
        set { d.set(newValue, forKey: "llmModelID") }
    }

    /// "speed" | "balanced" | "quality"
    static var performancePreference: String {
        get { d.string(forKey: "performancePreference") ?? "balanced" }
        set { d.set(newValue, forKey: "performancePreference") }
    }

    static var doubleTapHandsFree: Bool {
        get { d.object(forKey: "doubleTapHandsFree") as? Bool ?? true }
        set { d.set(newValue, forKey: "doubleTapHandsFree") }
    }

    /// "light" | "standard" | "heavy" — how aggressively the LLM may rewrite.
    static var cleanupLevel: String {
        get { d.string(forKey: "cleanupLevel") ?? "standard" }
        set { d.set(newValue, forKey: "cleanupLevel") }
    }

    /// Trailing spoken actions: "press enter", "send it".
    static var spokenCommandsEnabled: Bool {
        get { d.object(forKey: "spokenCommandsEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "spokenCommandsEnabled") }
    }

    /// Learn dictionary replacements from the user's post-paste corrections.
    static var autoLearnEnabled: Bool {
        get { d.object(forKey: "autoLearnEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoLearnEnabled") }
    }

    /// CoreAudio device UID of the preferred microphone; "" = system default.
    /// When the device is absent (headset unplugged, lid closed) we fall back to default.
    static var preferredMicUID: String {
        get { d.string(forKey: "preferredMicUID") ?? "" }
        set { d.set(newValue, forKey: "preferredMicUID") }
    }

    /// Boost quiet/whispered speech with automatic gain before ASR.
    static var whisperModeEnabled: Bool {
        get { d.bool(forKey: "whisperModeEnabled") }
        set { d.set(newValue, forKey: "whisperModeEnabled") }
    }

    /// Keep audio of failed dictations for retry from History.
    static var dictationRecoveryEnabled: Bool {
        get { d.object(forKey: "dictationRecoveryEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "dictationRecoveryEnabled") }
    }
}
