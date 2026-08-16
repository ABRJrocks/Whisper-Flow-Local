@preconcurrency import AVFoundation
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT v3 (0.6B, 25 European languages) via FluidAudio CoreML.
/// Models live in ~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml/.
final class ParakeetEngine: ASREngine, @unchecked Sendable {
    let id = "parakeet"
    let displayName = "Parakeet TDT v3 (FluidAudio)"

    private let lock = NSLock()
    private var manager: AsrManager?

    func supports(locale: Locale) async -> Bool {
        guard let lang = locale.language.languageCode?.identifier else { return false }
        return ASRRouter.parakeetLanguages.contains(lang)
    }

    func isReady(locale: Locale) async -> Bool {
        guard await supports(locale: locale) else { return false }
        // On-disk check only; never triggers a download.
        return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
    }

    /// Downloads (~1 GB, once) and loads the v3 CoreML models. Model is language-universal,
    /// so `locale` only gates the call, it doesn't change what's downloaded.
    func prepare(locale: Locale) async throws {
        if currentManager() != nil { return }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        try await installManager(models: models)
    }

    func startSession(locale: Locale, onPartial: (@Sendable (String) -> Void)?) async throws -> ASRSession {
        guard AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3) else {
            throw ASRError.engineNotReady("Parakeet")
        }
        let manager: AsrManager
        if let loaded = currentManager() {
            manager = loaded
        } else {
            let models = try await AsrModels.loadFromCache(version: .v3)
            manager = try await installManager(models: models)
        }
        // ponytail: onPartial ignored — TDT batch decode in finish() only.
        // FluidAudio's StreamingAsrManager is a protocol zoo; wire it up if live partials become a requirement.
        let hint = locale.language.languageCode.flatMap { Language(rawValue: $0.identifier) }
        return ParakeetSession(manager: manager, language: hint)
    }

    // MARK: - Manager cache

    private func currentManager() -> AsrManager? {
        lock.lock()
        defer { lock.unlock() }
        return manager
    }

    /// ponytail: concurrent prepare() calls may both load models; last one wins, both work.
    /// Serialize with a shared Task if double-loading ~1GB of CoreML ever hurts.
    @discardableResult
    private func installManager(models: AsrModels) async throws -> AsrManager {
        let created = AsrManager(config: .default, models: models)
        return storeManager(created)
    }

    private func storeManager(_ created: AsrManager) -> AsrManager {
        lock.lock()
        defer { lock.unlock() }
        if let existing = manager { return existing }
        manager = created
        return created
    }
}

/// Accumulates 16kHz mono Float32 and runs one batch transcription in finish().
/// ponytail: buffer grows ~3.8 MB/min of speech; fine for dictation-length sessions.
/// Switch to chunked/disk-backed feeding if hour-long sessions ever appear.
private final class ParakeetSession: ASRSession, @unchecked Sendable {
    private let manager: AsrManager
    private let language: Language?
    private let converter: BufferConverter
    private let lock = NSLock()
    private var samples: [Float] = []

    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    init(manager: AsrManager, language: Language?) {
        self.manager = manager
        self.language = language
        self.converter = BufferConverter(target: Self.targetFormat)
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer),
            let channel = converted.floatChannelData
        else { return }
        let count = Int(converted.frameLength)
        guard count > 0 else { return }
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: count))
        lock.unlock()
    }

    func finish() async throws -> ASRResult {
        let audio = takeSamples()

        // FluidAudio throws invalidAudioData below 0.3s; an empty transcript is the honest answer.
        guard audio.count >= ASRConstants.minimumRequiredSamples(forSampleRate: 16_000) else {
            return ASRResult(text: "", engineID: "parakeet", inferenceSeconds: 0)
        }
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(audio, decoderState: &decoderState, language: language)
        return ASRResult(text: result.text, engineID: "parakeet", inferenceSeconds: result.processingTime)
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
