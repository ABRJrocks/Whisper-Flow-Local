@preconcurrency import AVFoundation
import Foundation

struct ASRResult: Sendable {
    let text: String
    let engineID: String
    let inferenceSeconds: Double
}

/// A live per-dictation session. Feed PCM buffers in any format; finish returns the transcript.
protocol ASRSession: AnyObject, Sendable {
    func feed(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> ASRResult
    func cancel() async
}

/// One speech-recognition backend (Apple, Parakeet, Whisper).
protocol ASREngine: AnyObject, Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Locales this engine can handle at all (installed or not).
    func supports(locale: Locale) async -> Bool
    /// True when the model is installed and the engine can start immediately.
    func isReady(locale: Locale) async -> Bool
    /// Download/load whatever is needed for this locale.
    func prepare(locale: Locale) async throws
    func startSession(locale: Locale, onPartial: (@Sendable (String) -> Void)?) async throws -> ASRSession
}

enum ASRError: LocalizedError {
    case engineNotReady(String)
    case noEngineForLanguage(String)

    var errorDescription: String? {
        switch self {
        case .engineNotReady(let name): return "\(name) is not installed yet. Open Model Center to install it."
        case .noEngineForLanguage(let lang): return "No installed engine supports “\(lang)”."
        }
    }
}
