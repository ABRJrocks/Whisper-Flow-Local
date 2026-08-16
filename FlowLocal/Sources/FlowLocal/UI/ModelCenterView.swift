import SwiftUI

struct ModelCenterView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Languages")
                    .font(.headline)
                Text("Per-language readiness. Apple models download per language; Parakeet and Whisper are single installs that cover many languages at once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(AppLanguages.all.filter { $0.id != "auto" }, id: \.id) { lang in
                    LanguageRow(languageID: lang.id, name: lang.name)
                }

                Divider().padding(.vertical, 4)

                Text("Speech Recognition Engines")
                    .font(.headline)
                ForEach(ASRRouter.shared.all.map(EngineBox.init)) { box in
                    ASREngineCard(engine: box.engine)
                }

                Divider().padding(.vertical, 4)

                Text("AI Cleanup Models")
                    .font(.headline)
                LLMSection()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Per-language readiness

private struct LanguageRow: View {
    let languageID: String
    let name: String

    private enum AppleState { case checking, unsupported, installed, notInstalled, installing, failed(String) }
    @State private var appleState: AppleState = .checking
    /// Installed engine bundles already covering this language ("Parakeet", "Whisper").
    @State private var coveredBy: [String] = []

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Text(coverageLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            appleControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .task { await refresh() }
    }

    private var coverageLine: String {
        var parts = coveredBy
        if case .installed = appleState { parts.insert("Apple", at: 0) }
        return parts.isEmpty ? "No installed engine covers this language yet" : "Ready via \(parts.joined(separator: ", "))"
    }

    @ViewBuilder
    private var appleControl: some View {
        switch appleState {
        case .checking:
            ProgressView().controlSize(.small)
        case .installed:
            Label("Apple model installed", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        case .notInstalled:
            Button("Install Apple model") { install() }.controlSize(.small)
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Downloading…").font(.caption).foregroundStyle(.secondary)
            }
        case .unsupported:
            Text("Apple model unavailable")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 4) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: 180, alignment: .trailing)
                Button("Retry") { install() }.controlSize(.small)
            }
        }
    }

    private func refresh() async {
        let locale = Locale(identifier: languageID)
        let router = ASRRouter.shared

        var covered: [String] = []
        if await router.parakeet.isReady(locale: locale) { covered.append("Parakeet") }
        if await router.whisper.isReady(locale: locale) { covered.append("Whisper") }
        coveredBy = covered

        if await router.apple.supports(locale: locale) {
            appleState = await SpeechModel.isInstalled(locale: locale) ? .installed : .notInstalled
        } else {
            appleState = .unsupported
        }
    }

    private func install() {
        appleState = .installing
        Task {
            do {
                try await SpeechModel.ensureInstalled(locale: Locale(identifier: languageID))
                await refresh()
            } catch {
                appleState = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - ASR engines

/// Identifiable wrapper so an existential engine can drive ForEach.
private struct EngineBox: Identifiable {
    let engine: any ASREngine
    var id: String { engine.id }
}

private struct EngineMeta {
    let description: String
    let sizeAndLicense: String
}

// ponytail: static metadata keyed by engine id; new engines get a generic fallback line.
private let engineMeta: [String: EngineMeta] = [
    "apple": EngineMeta(
        description: "Built into macOS. Fast, private, and managed by the system.",
        sizeAndLicense: "System model · downloaded by macOS · Apple license"
    ),
    "parakeet": EngineMeta(
        description: "NVIDIA Parakeet TDT v3 — best accuracy for English and 24 European languages.",
        sizeAndLicense: "≈2.5 GB download · CC-BY-4.0"
    ),
    "whisper": EngineMeta(
        description: "OpenAI Whisper large-v3-turbo — broad multilingual coverage, including Urdu, Arabic, and Hindi.",
        sizeAndLicense: "≈1.6 GB download · MIT"
    ),
]

private struct ASREngineCard: View {
    let engine: any ASREngine

    private enum Status { case checking, ready, notInstalled, installing, failed(String) }
    @State private var status: Status = .checking

    private var meta: EngineMeta {
        engineMeta[engine.id] ?? EngineMeta(description: "Speech recognition engine.", sizeAndLicense: "")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.displayName).font(.system(size: 13, weight: .semibold))
                Text(meta.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !meta.sizeAndLicense.isEmpty {
                    Text(meta.sizeAndLicense)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            statusControl
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .task(id: PrefsModel.shared.languageID) { await refresh() } // observable → re-runs on language change
    }

    @ViewBuilder
    private var statusControl: some View {
        switch status {
        case .checking:
            ProgressView().controlSize(.small)
        case .ready:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        case .notInstalled:
            Button("Install") { install() }
                .controlSize(.small)
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…").font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 4) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: 180, alignment: .trailing)
                Button("Retry") { install() }.controlSize(.small)
            }
        }
    }

    private func refresh() async {
        status = .checking
        let locale = Locale(identifier: Prefs.languageID)
        status = await engine.isReady(locale: locale) ? .ready : .notInstalled
    }

    private func install() {
        status = .installing
        let locale = Locale(identifier: Prefs.languageID)
        Task {
            do {
                try await engine.prepare(locale: locale)
                status = .ready
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - LLM models

private struct LLMSection: View {
    @State private var installed: [String] = []
    @State private var activeID: String?
    @State private var installProgress: [String: Double] = [:]
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(LLMManager.shared.availableModels) { model in
                row(for: model)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("The active model refines transcripts on-device. Larger models are more accurate but need more memory.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
    }

    private func row(for model: LLMManager.ModelOption) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName).font(.system(size: 13, weight: .semibold))
                Text(String(format: "%.1f GB · needs %d GB RAM", model.sizeGB, model.minRAMGB))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            controls(for: model)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func controls(for model: LLMManager.ModelOption) -> some View {
        if let progress = installProgress[model.id] {
            HStack(spacing: 6) {
                ProgressView(value: progress).frame(width: 100)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if installed.contains(model.id) {
            HStack(spacing: 8) {
                if activeID == model.id {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Button("Activate") { activate(model) }.controlSize(.small)
                }
                Button {
                    delete(model)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(model.displayName)")
            }
        } else {
            Button("Install") { install(model) }.controlSize(.small)
        }
    }

    private func refresh() {
        installed = LLMManager.shared.installedModels()
        activeID = LLMManager.shared.activeModelID
    }

    private func install(_ model: LLMManager.ModelOption) {
        installProgress[model.id] = 0
        errorMessage = nil
        let id = model.id
        Task {
            do {
                try await LLMManager.shared.install(modelID: id) { fraction in
                    Task { @MainActor in installProgress[id] = fraction }
                }
                installProgress[id] = nil
                refresh()
            } catch {
                installProgress[id] = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func activate(_ model: LLMManager.ModelOption) {
        errorMessage = nil
        Task {
            do {
                try await LLMManager.shared.activate(modelID: model.id)
                refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ model: LLMManager.ModelOption) {
        do {
            try LLMManager.shared.delete(modelID: model.id)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
