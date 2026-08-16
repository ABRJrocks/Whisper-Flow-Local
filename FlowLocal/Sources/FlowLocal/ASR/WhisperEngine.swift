@preconcurrency import AVFoundation
import Foundation
import WhisperKit

/// Whisper (WhisperKit) engine: Urdu + universal multilingual fallback.
/// Batch engine — accumulates audio, transcribes on finish. No partials.
final class WhisperEngine: ASREngine, @unchecked Sendable {
    let id = "whisper"
    let displayName = "Whisper (WhisperKit)"

    /// large-v3 turbo CoreML variant from argmaxinc/whisperkit-coreml (~632 MB download).
    static let modelName = "openai_whisper-large-v3-v20240930_turbo"
    private static let modelRepo = "argmaxinc/whisperkit-coreml"

    /// Explicit download base so isReady can check the exact folder WhisperKit's HubApi
    /// writes to: <base>/models/argmaxinc/whisperkit-coreml/<modelName>.
    private static let downloadBase = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(component: "FlowLocal")

    private static var modelFolder: URL {
        downloadBase
            .appending(component: "models")
            .appending(component: modelRepo)
            .appending(component: modelName)
    }

    private let lock = NSLock()
    private var whisperKit: WhisperKit?

    func supports(locale: Locale) async -> Bool {
        // "auto" = per-dictation language detection (language hint nil).
        locale.identifier == "auto" || Self.whisperLanguageCode(for: locale) != nil
    }

    func isReady(locale: Locale) async -> Bool {
        guard await supports(locale: locale) else { return false }
        // Model folder on disk with all three compiled models; never triggers a download.
        let fm = FileManager.default
        return ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            fm.fileExists(atPath: Self.modelFolder.appending(component: "\(name).mlmodelc").path)
                || fm.fileExists(atPath: Self.modelFolder.appending(component: "\(name).mlpackage").path)
        }
    }

    func prepare(locale: Locale) async throws {
        if currentKit() != nil { return }

        let config = WhisperKitConfig(
            model: Self.modelName,
            downloadBase: Self.downloadBase,
            modelRepo: Self.modelRepo,
            load: true,
            download: true
        )
        let kit = try await WhisperKit(config)
        setKit(kit)
    }

    func startSession(locale: Locale, onPartial: (@Sendable (String) -> Void)?) async throws -> ASRSession {
        guard let kit = currentKit() else { throw ASRError.engineNotReady("Whisper") }
        // onPartial ignored: batch engine, transcript arrives at finish().
        return WhisperSession(whisperKit: kit, language: Self.whisperLanguageCode(for: locale), engineID: id)
    }

    private func currentKit() -> WhisperKit? {
        lock.lock()
        defer { lock.unlock() }
        return whisperKit
    }

    private func setKit(_ kit: WhisperKit) {
        lock.lock()
        defer { lock.unlock() }
        whisperKit = kit
    }

    /// Whisper ISO 639-1 code for a locale, from WhisperKit's own language map.
    /// Always returned as an explicit hint — Hindi/Urdu confuse auto-detect.
    private static func whisperLanguageCode(for locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier(.alpha2) else { return nil }
        return Constants.languageCodes.contains(code) ? code : nil
    }
}

/// Accumulates 16kHz mono Float32 samples, transcribes in one shot on finish.
/// ponytail: whole take kept in RAM — 16kHz Float32 ≈ 3.8 MB/min, ~77 MB at the
/// 20-min cap. Fine; stream to a temp file if the cap ever grows.
private final class WhisperSession: ASRSession, @unchecked Sendable {
    private static let format16kMono = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(WhisperKit.sampleRate),
        channels: 1,
        interleaved: false
    )!

    private let whisperKit: WhisperKit
    private let language: String?
    private let engineID: String
    private let converter = BufferConverter(target: WhisperSession.format16kMono)
    private let lock = NSLock()
    private var samples: [Float] = []

    init(whisperKit: WhisperKit, language: String?, engineID: String) {
        self.whisperKit = whisperKit
        self.language = language
        self.engineID = engineID
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer),
              let channel = converted.floatChannelData?[0] else { return }
        let frames = Int(converted.frameLength)
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
        lock.unlock()
    }

    func finish() async throws -> ASRResult {
        let audio = takeSamples()
        guard !audio.isEmpty else {
            return ASRResult(text: "", engineID: engineID, inferenceSeconds: 0)
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language,   // explicit hint, e.g. "ur" — never auto-detect for ur/hi
            chunkingStrategy: .vad // parallel windows for long dictations
        )
        let start = Date()
        let results = try await whisperKit.transcribe(audioArray: audio, decodeOptions: options)
        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return ASRResult(text: text, engineID: engineID, inferenceSeconds: Date().timeIntervalSince(start))
    }

    func cancel() async {
        _ = takeSamples()
    }

    private func takeSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let audio = samples
        samples = []
        return audio
    }
}
