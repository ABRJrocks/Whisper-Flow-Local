@preconcurrency import AVFoundation
import Foundation
import Speech

/// On-device ASR via the macOS 26 SpeechAnalyzer / SpeechTranscriber API.
/// ponytail: native OS engine for MVP; Parakeet/Whisper/Qwen engines slot in behind this later.
enum TranscriberError: LocalizedError {
    case localeUnsupported(String)
    case noAnalyzerFormat

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let id): return "On-device transcription does not support locale \(id)."
        case .noAnalyzerFormat: return "SpeechAnalyzer reported no usable audio format."
        }
    }
}

enum SpeechModel {
    /// Ensure the on-device model for `locale` is installed. Downloads via the OS if missing.
    static func ensureInstalled(locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            throw TranscriberError.localeUnsupported(locale.identifier)
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    static func isInstalled(locale: Locale) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }
}

/// One live transcription session: feed PCM buffers, finish, get text.
final class TranscriptionSession: @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let collector: Task<String, Error>
    private let converter: BufferConverter
    let analyzerFormat: AVAudioFormat

    private init(
        analyzer: SpeechAnalyzer,
        transcriber: SpeechTranscriber,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        collector: Task<String, Error>,
        analyzerFormat: AVAudioFormat
    ) {
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.inputContinuation = continuation
        self.collector = collector
        self.analyzerFormat = analyzerFormat
        self.converter = BufferConverter(target: analyzerFormat)
    }

    /// `onPartial` receives (finalizedSoFar + volatile) as recognition progresses.
    static func start(locale: Locale, onPartial: (@Sendable (String) -> Void)? = nil) async throws -> TranscriptionSession {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriberError.noAnalyzerFormat
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let collector = Task<String, Error> {
            var finalText = ""
            for try await result in transcriber.results {
                let piece = String(result.text.characters)
                if result.isFinal {
                    finalText += piece
                    onPartial?(finalText)
                } else {
                    onPartial?(finalText + piece)
                }
            }
            return finalText
        }

        try await analyzer.start(inputSequence: stream)
        return TranscriptionSession(
            analyzer: analyzer,
            transcriber: transcriber,
            continuation: continuation,
            collector: collector,
            analyzerFormat: format
        )
    }

    /// Feed a buffer in any PCM format; converted to the analyzer format internally.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer) else { return }
        inputContinuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Stop input and wait for the final transcript.
    func finish() async throws -> String {
        inputContinuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value
    }

    func cancel() async {
        inputContinuation.finish()
        collector.cancel()
        await analyzer.cancelAndFinishNow()
    }
}

/// Converts arbitrary input PCM buffers to a fixed target format.
final class BufferConverter: @unchecked Sendable {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(target: AVAudioFormat) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        if converter == nil || sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            sourceFormat = buffer.format
        }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return nil }
        return out.frameLength > 0 ? out : nil
    }
}
