import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @State private var prefs = PrefsModel.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @State private var mics = MicSelector.inputDevices()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Play sounds", isOn: $prefs.soundsEnabled)
                Toggle("Show live transcript while dictating", isOn: $prefs.showPartialTranscript)
                Toggle("Spoken commands (\"press enter\", \"send it\")", isOn: $prefs.spokenCommandsEnabled)
            }

            Section("Language") {
                Picker("Dictation language", selection: $prefs.languageID) {
                    ForEach(AppLanguages.all, id: \.id) { lang in
                        Text(lang.name).tag(lang.id)
                    }
                }
                if prefs.languageID == "auto" {
                    Text("Auto-detect uses the Whisper engine (installable in the Models tab) and picks the spoken language per dictation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Microphone") {
                Picker("Input device", selection: $prefs.preferredMicUID) {
                    Text("System default").tag("")
                    ForEach(mics) { mic in
                        Text(mic.name).tag(mic.uid)
                    }
                    if !prefs.preferredMicUID.isEmpty, !mics.contains(where: { $0.uid == prefs.preferredMicUID }) {
                        Text("Preferred mic (disconnected)").tag(prefs.preferredMicUID)
                    }
                }
                Text("When the preferred mic isn't available (headset unplugged, lid closed), the system default is used automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Boost quiet speech (Whisper mode)", isOn: $prefs.whisperModeEnabled)
                Toggle("Keep audio of failed dictations for retry", isOn: $prefs.dictationRecoveryEnabled)
            }
            .onAppear { mics = MicSelector.inputDevices() }

            Section("Hands-free") {
                Toggle("Double-tap Fn starts hands-free dictation", isOn: $prefs.doubleTapHandsFree)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Stop after silence")
                        Spacer()
                        Text(prefs.silenceTimeoutSeconds <= 0 ? "Off" : "\(Int(prefs.silenceTimeoutSeconds))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $prefs.silenceTimeoutSeconds, in: 0...5, step: 1)
                        .accessibilityLabel("Silence timeout in seconds, 0 is off")
                }
                Picker("Session limit", selection: $prefs.sessionLimitMinutes) {
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("20 minutes").tag(20)
                    Text("30 minutes").tag(30)
                }
            }
        }
        .formStyle(.grouped)
    }
}
