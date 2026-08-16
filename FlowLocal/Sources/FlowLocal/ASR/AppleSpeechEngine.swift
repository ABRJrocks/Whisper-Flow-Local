@preconcurrency import AVFoundation
import Foundation
import Speech

/// Wraps the macOS 26 SpeechAnalyzer/SpeechTranscriber behind the common engine protocol.
final class AppleSpeechEngine: ASREngine {
    let id = "apple"
    let displayName = "Apple On-Device Speech"

    func supports(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    func isReady(locale: Locale) async -> Bool {
        await SpeechModel.isInstalled(locale: locale)
    }

    func prepare(locale: Locale) async throws {
        try await SpeechModel.ensureInstalled(locale: locale)
    }

    func startSession(locale: Locale, onPartial: (@Sendable (String) -> Void)?) async throws -> ASRSession {
        let session = try await TranscriptionSession.start(locale: locale, onPartial: onPartial)
        return AppleSpeechSession(session: session)
    }
}

private final class AppleSpeechSession: ASRSession {
    private let session: TranscriptionSession
    private let startedAt = Date()

    init(session: TranscriptionSession) {
        self.session = session
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        session.feed(buffer)
    }

    func finish() async throws -> ASRResult {
        let text = try await session.finish()
        return ASRResult(text: text, engineID: "apple", inferenceSeconds: Date().timeIntervalSince(startedAt))
    }

    func cancel() async {
        await session.cancel()
    }
}
