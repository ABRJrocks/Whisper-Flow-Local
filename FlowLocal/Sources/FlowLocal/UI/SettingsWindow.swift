import SwiftUI

// MARK: - Observable mirror of Prefs (UserDefaults has no change notification we care to wire; writes go straight through)

@MainActor
@Observable
final class PrefsModel {
    static let shared = PrefsModel()

    var languageID = Prefs.languageID { didSet { Prefs.languageID = languageID } }
    var preferredEngine = Prefs.preferredEngine { didSet { Prefs.preferredEngine = preferredEngine } }
    var llmRefinementEnabled = Prefs.llmRefinementEnabled { didSet { Prefs.llmRefinementEnabled = llmRefinementEnabled } }
    var historyEnabled = Prefs.historyEnabled { didSet { Prefs.historyEnabled = historyEnabled } }
    var historyRetentionDays = Prefs.historyRetentionDays { didSet { Prefs.historyRetentionDays = historyRetentionDays } }
    var contextAwarenessEnabled = Prefs.contextAwarenessEnabled { didSet { Prefs.contextAwarenessEnabled = contextAwarenessEnabled } }
    var showPartialTranscript = Prefs.showPartialTranscript { didSet { Prefs.showPartialTranscript = showPartialTranscript } }
    var silenceTimeoutSeconds = Prefs.silenceTimeoutSeconds { didSet { Prefs.silenceTimeoutSeconds = silenceTimeoutSeconds } }
    var sessionLimitMinutes = Prefs.sessionLimitMinutes { didSet { Prefs.sessionLimitMinutes = sessionLimitMinutes } }
    var soundsEnabled = Prefs.soundsEnabled { didSet { Prefs.soundsEnabled = soundsEnabled } }
    var performancePreference = Prefs.performancePreference { didSet { Prefs.performancePreference = performancePreference } }
    var doubleTapHandsFree = Prefs.doubleTapHandsFree { didSet { Prefs.doubleTapHandsFree = doubleTapHandsFree } }
    var cleanupLevel = Prefs.cleanupLevel { didSet { Prefs.cleanupLevel = cleanupLevel } }
    var spokenCommandsEnabled = Prefs.spokenCommandsEnabled { didSet { Prefs.spokenCommandsEnabled = spokenCommandsEnabled } }
    var autoLearnEnabled = Prefs.autoLearnEnabled { didSet { Prefs.autoLearnEnabled = autoLearnEnabled } }
    var preferredMicUID = Prefs.preferredMicUID { didSet { Prefs.preferredMicUID = preferredMicUID } }
    var whisperModeEnabled = Prefs.whisperModeEnabled { didSet { Prefs.whisperModeEnabled = whisperModeEnabled } }
    var dictationRecoveryEnabled = Prefs.dictationRecoveryEnabled { didSet { Prefs.dictationRecoveryEnabled = dictationRecoveryEnabled } }
}

// MARK: - Root

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            IntelligenceSettings()
                .tabItem { Label("Intelligence", systemImage: "sparkles") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            PersonalizationSettings()
                .tabItem { Label("Personalization", systemImage: "person.text.rectangle") }
            ModelCenterView()
                .tabItem { Label("Models", systemImage: "square.and.arrow.down.on.square") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}

// MARK: - About / Licenses

struct AboutSettings: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("FlowLocal").font(.title2.bold())
            Text("Version \(version) — local-first voice dictation for macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(thirdPartyNotices)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
    }
}

let thirdPartyNotices = """
THIRD-PARTY NOTICES

FlowLocal bundles or downloads the following third-party software and models.
All processing happens on this Mac; nothing is sent to any server.

GRDB.swift — SQLite toolkit
  Copyright Gwendal Roué. MIT License.

FluidAudio — Parakeet CoreML runtime
  Copyright Fluid Inference. Apache License 2.0.

WhisperKit — Whisper CoreML runtime
  Copyright Argmax, Inc. MIT License.

MLX Swift / mlx-swift-lm — local LLM runtime
  Copyright Apple Inc. and MLX contributors. MIT License.

Parakeet TDT v3 (0.6b) speech model
  Copyright NVIDIA Corporation. CC-BY-4.0.

Whisper large-v3-turbo speech model
  Copyright OpenAI. MIT License.

Apple Speech, SwiftUI, and other system frameworks are provided by macOS
under the Apple software license.
"""
