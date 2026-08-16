import Foundation
import HuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

// MARK: - Hugging Face hub plumbing

/// Bridges swift-huggingface / swift-transformers to mlx-swift-lm 3.x, which ships
/// no downloader or tokenizer of its own. These structs mirror the expansions of
/// mlx-swift-lm's `#hubDownloader()` / `#huggingFaceTokenizerLoader()` macros
/// (Libraries/MLXHuggingFaceMacros), written out so we control the cache handle.
enum LLMHub {
    /// Same patterns as MLXLMCommon.modelDownloadPatterns (package-internal there).
    static let downloadPatterns = ["*.safetensors", "*.json", "*.jinja"]

    /// Python-compatible HF cache (`~/.cache/huggingface/hub` unsandboxed,
    /// `Library/Caches/huggingface/hub` sandboxed; HF_HUB_CACHE/HF_HOME override).
    static let cache = HubCache.default
    static let client = HubClient(cache: cache)

    static func repoDirectory(modelID: String) -> URL? {
        guard let repo = Repo.ID(rawValue: modelID) else { return nil }
        return cache.repoDirectory(repo: repo, kind: .model)
    }

    struct HubDownloader: MLXLMCommon.Downloader {
        func download(
            id: String,
            revision: String?,
            matching patterns: [String],
            useLatest: Bool,
            progressHandler: @Sendable @escaping (Progress) -> Void
        ) async throws -> URL {
            guard let repo = Repo.ID(rawValue: id) else {
                throw LLMManagerError.invalidModelID(id)
            }
            return try await LLMHub.client.downloadSnapshot(
                of: repo,
                revision: revision ?? "main",
                matching: patterns,
                progressHandler: { @MainActor progress in progressHandler(progress) }
            )
        }
    }

    struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
        func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
            TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
        }
    }

    struct TokenizerBridge: MLXLMCommon.Tokenizer {
        private let upstream: any Tokenizers.Tokenizer

        init(_ upstream: any Tokenizers.Tokenizer) {
            self.upstream = upstream
        }

        func encode(text: String, addSpecialTokens: Bool) -> [Int] {
            upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
        }

        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
            upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
        }

        func convertTokenToId(_ token: String) -> Int? {
            upstream.convertTokenToId(token)
        }

        func convertIdToToken(_ id: Int) -> String? {
            upstream.convertIdToToken(id)
        }

        var bosToken: String? { upstream.bosToken }
        var eosToken: String? { upstream.eosToken }
        var unknownToken: String? { upstream.unknownToken }

        func applyChatTemplate(
            messages: [[String: any Sendable]],
            tools: [[String: any Sendable]]?,
            additionalContext: [String: any Sendable]?
        ) throws -> [Int] {
            do {
                return try upstream.applyChatTemplate(
                    messages: messages, tools: tools, additionalContext: additionalContext)
            } catch Tokenizers.TokenizerError.missingChatTemplate {
                throw MLXLMCommon.TokenizerError.missingChatTemplate
            }
        }
    }

    /// Load (downloading into the HF cache if needed) a `ModelContainer` for a repo ID.
    static func loadContainer(
        modelID: String,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws -> ModelContainer {
        try await LLMModelFactory.shared.loadContainer(
            from: HubDownloader(),
            using: TransformersTokenizerLoader(),
            configuration: ModelConfiguration(id: modelID),
            progressHandler: progressHandler
        )
    }
}

enum LLMManagerError: LocalizedError {
    case invalidModelID(String)
    case modelNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidModelID(let id): return "Invalid model ID: \(id)"
        case .modelNotAvailable(let id): return "Model not available on this hardware: \(id)"
        }
    }
}

// MARK: - LLMManager

/// Owns the model registry, install/delete, and the single active `MLXRefiner`.
/// Only one model is loaded at a time; `activate` unloads the previous one first.
final class LLMManager: @unchecked Sendable {

    static let shared = LLMManager()
    private init() {}

    struct ModelOption: Identifiable, Sendable {
        var id: String
        var displayName: String
        var sizeGB: Double
        var minRAMGB: Int
    }

    /// Verified on Hugging Face 2026-07-22 via the API; sizeGB = safetensors bytes.
    private static let registry: [ModelOption] = [
        ModelOption(
            id: "mlx-community/Qwen3.5-0.8B-4bit",
            displayName: "Qwen3.5 0.8B (fast)", sizeGB: 0.63, minRAMGB: 8),
        ModelOption(
            id: "mlx-community/Qwen3.5-2B-4bit",
            displayName: "Qwen3.5 2B (balanced)", sizeGB: 1.72, minRAMGB: 16),
        ModelOption(
            id: "mlx-community/Qwen3.5-4B-4bit",
            displayName: "Qwen3.5 4B (quality)", sizeGB: 3.03, minRAMGB: 24),
    ]

    private let lock = NSLock()
    private var current: MLXRefiner?

    // MARK: Registry

    var availableModels: [ModelOption] {
        let ram = HardwareProfiler.current().memoryGB
        return Self.registry.filter { $0.minRAMGB <= ram }
    }

    func installedModels() -> [String] {
        Self.registry.map(\.id).filter { isInstalled(modelID: $0) }
    }

    private func isInstalled(modelID: String) -> Bool {
        guard let repoDir = LLMHub.repoDirectory(modelID: modelID) else { return false }
        let snapshots = repoDir.appendingPathComponent("snapshots")
        guard
            let enumerator = FileManager.default.enumerator(
                at: snapshots, includingPropertiesForKeys: nil)
        else { return false }
        for case let url as URL in enumerator where url.pathExtension == "safetensors" {
            // Snapshot entries are symlinks into blobs/; a resolvable link means
            // the weight file finished downloading.
            if FileManager.default.fileExists(atPath: url.resolvingSymlinksInPath().path) {
                return true
            }
        }
        return false
    }

    // MARK: Install / delete

    func install(modelID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await LLMHub.HubDownloader().download(
            id: modelID,
            revision: "main",
            matching: LLMHub.downloadPatterns,
            useLatest: false,
            progressHandler: { p in
                progress(min(1, max(0, p.fractionCompleted)))
            }
        )
        progress(1)
    }

    func delete(modelID: String) throws {
        guard let repoDir = LLMHub.repoDirectory(modelID: modelID) else {
            throw LLMManagerError.invalidModelID(modelID)
        }
        // Drop the in-memory model if it's the one being deleted (async unload
        // isn't possible here; releasing the reference frees the weights).
        lock.withLock {
            if current?.modelID == modelID { current = nil }
        }
        if FileManager.default.fileExists(atPath: repoDir.path) {
            try FileManager.default.removeItem(at: repoDir)
        }
        if Prefs.llmModelID == modelID {
            Prefs.llmModelID = ""
        }
    }

    // MARK: Activation

    func activate(modelID: String) async throws {
        // Unload the previous model first: never two models resident at once.
        let previous = lock.withLock { () -> MLXRefiner? in
            let p = current
            current = nil
            return p
        }
        await previous?.unload()

        let refiner = MLXRefiner(modelID: modelID)
        try await refiner.load()
        lock.withLock { current = refiner }
        Prefs.llmModelID = modelID
    }

    var activeModelID: String? {
        lock.withLock { current?.modelID }
    }

    var refiner: (any TextRefiner)? {
        lock.withLock { current }
    }

    /// Load `Prefs.llmModelID` at startup if set, installed-capable, and not throttled.
    /// Never throws outward.
    func warmUpIfConfigured() async {
        let modelID = Prefs.llmModelID
        guard !modelID.isEmpty, activeModelID != modelID else { return }
        guard availableModels.contains(where: { $0.id == modelID }) else {
            log.warning("LLM warm-up skipped: \(modelID) exceeds this machine's RAM tier")
            return
        }
        guard await MainActor.run(body: { AdaptivePerformanceController.shared.allowHeavyModels })
        else {
            log.info("LLM warm-up skipped: throttled")
            return
        }
        do {
            try await activate(modelID: modelID)
        } catch {
            log.error("LLM warm-up failed for \(modelID): \(error.localizedDescription)")
        }
    }

    func unloadForMemoryPressure() async {
        let previous = lock.withLock { () -> MLXRefiner? in
            let p = current
            current = nil
            return p
        }
        if let previous {
            await previous.unload()
            log.info("LLM unloaded for memory pressure")
        }
    }
}
