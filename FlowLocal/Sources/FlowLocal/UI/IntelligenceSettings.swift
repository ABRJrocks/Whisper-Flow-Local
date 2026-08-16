import SwiftUI

struct IntelligenceSettings: View {
    @State private var prefs = PrefsModel.shared

    var body: some View {
        Form {
            Section("Speech Recognition") {
                Picker("Engine", selection: $prefs.preferredEngine) {
                    Text("Automatic (recommended)").tag("auto")
                    Text("Apple On-Device Speech").tag("apple")
                    Text("Parakeet TDT v3").tag("parakeet")
                    Text("Whisper large-v3-turbo").tag("whisper")
                }
                Text("Automatic picks the best installed engine for your language. Install engines in the Models tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI Cleanup") {
                Toggle("Refine transcripts with a local language model", isOn: $prefs.llmRefinementEnabled)
                if prefs.llmRefinementEnabled {
                    Picker("Intensity", selection: $prefs.cleanupLevel) {
                        Text("Light").tag("light")
                        Text("Standard").tag("standard")
                        Text("Heavy").tag("heavy")
                    }
                    .pickerStyle(.segmented)
                    Text("Light only removes fillers and fixes punctuation. Heavy may restructure long dictation into clear sentences or lists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Fixes punctuation, casing, and filler words on-device. Falls back to rule-based cleanup when the model is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Performance") {
                Picker("Prefer", selection: $prefs.performancePreference) {
                    Text("Speed").tag("speed")
                    Text("Balanced").tag("balanced")
                    Text("Quality").tag("quality")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}
