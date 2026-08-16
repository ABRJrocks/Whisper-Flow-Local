@preconcurrency import AVFoundation
import Foundation

/// Transcribe a saved recording (dictation recovery retry).
enum FileTranscriber {
    static func transcribe(url: URL, localeID: String) async throws -> String {
        let locale = Locale(identifier: localeID)
        guard let engine = await ASRRouter.shared.engine(for: locale) else {
            throw ASRError.noEngineForLanguage(localeID)
        }
        if await !engine.isReady(locale: locale) {
            try await engine.prepare(locale: locale)
        }
        let session = try await engine.startSession(locale: locale, onPartial: nil)

        let file = try AVAudioFile(forReading: url)
        let chunk: AVAudioFrameCount = 16384
        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
            try file.read(into: buffer, frameCount: chunk)
            guard buffer.frameLength > 0 else { break }
            session.feed(buffer)
        }
        let result = try await withTimeout(seconds: 120) { try await session.finish() }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
