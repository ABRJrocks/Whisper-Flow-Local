import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: WelcomeStep()
                case 1: PermissionsStep()
                case 2: SpeechModelStep()
                default: TryItStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            Divider()

            HStack {
                if page > 0 {
                    Button("Back") { step(-1) }
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0...lastPage, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityLabel("Step \(page + 1) of \(lastPage + 1)")
                Spacer()
                if page < lastPage {
                    Button("Continue") { step(1) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") {
                        Prefs.firstRunCompleted = true
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func step(_ delta: Int) {
        if UIMotion.reduced {
            page += delta
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { page += delta }
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Welcome to FlowLocal")
                .font(.largeTitle.bold())
            Text("Speak anywhere your cursor is — FlowLocal turns your voice into polished text, instantly.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Label {
                Text("100% local. Your voice and words never leave this Mac — no account, no cloud, no telemetry.")
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
            }
            .font(.callout)
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 440)
        }
    }
}

// MARK: - Step 2: Permissions

private struct PermissionsStep: View {
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axTrusted = AXIsProcessTrusted()
    // Poll while visible; the user grants Accessibility in System Settings, outside our process.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Two Permissions")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .center)
            Text("FlowLocal needs these to hear you and type for you. Both are used only while you dictate.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            permissionRow(
                title: "Microphone",
                detail: "Captures your voice while you hold the shortcut.",
                symbol: "mic.fill",
                granted: micStatus == .authorized
            ) {
                if micStatus == .notDetermined {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .audio)
                        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    }
                } else {
                    openSettings("Privacy_Microphone")
                }
            }

            permissionRow(
                title: "Accessibility",
                detail: "Lets FlowLocal detect the shortcut keys and insert text where your cursor is.",
                symbol: "accessibility",
                granted: axTrusted
            ) {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                openSettings("Privacy_Accessibility")
            }
        }
        .frame(maxWidth: 480)
        .onReceive(poll) { _ in
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            axTrusted = AXIsProcessTrusted()
        }
    }

    private func permissionRow(
        title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Grant…", action: action)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) permission: \(granted ? "granted" : "not granted")")
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Step 3: Speech model

private struct SpeechModelStep: View {
    private enum Status { case checking, installed, notInstalled, installing, failed(String) }
    @State private var status: Status = .checking

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Speech Model")
                .font(.largeTitle.bold())
            Text("macOS downloads a small on-device model for your language once. After that, dictation works entirely offline.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            switch status {
            case .checking:
                ProgressView("Checking…")
            case .installed:
                Label("Model installed and ready", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            case .notInstalled:
                Button("Download Model") { install() }
                    .buttonStyle(.borderedProminent)
            case .installing:
                ProgressView("Downloading… this can take a few minutes")
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { install() }
                }
            }
        }
        .task {
            status = await SpeechModel.isInstalled(locale: Locale(identifier: Prefs.languageID))
                ? .installed : .notInstalled
        }
    }

    private func install() {
        status = .installing
        Task {
            do {
                try await SpeechModel.ensureInstalled(locale: Locale(identifier: Prefs.languageID))
                status = .installed
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Step 4: Try it

private struct TryItStep: View {
    @State private var text = ""

    var body: some View {
        VStack(spacing: 18) {
            Text("Try It")
                .font(.largeTitle.bold())
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("Click below, then hold")
                    KeyCap("fn")
                    Text("or")
                    KeyCap("⌃")
                    KeyCap("⌥")
                    Text("and speak. Release to insert.")
                }
                .font(.callout)
                HStack(spacing: 4) {
                    Text("Double-tap")
                    KeyCap("fn")
                    Text("for hands-free ·")
                    KeyCap("esc")
                    Text("cancels")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: 460, minHeight: 140, maxHeight: 180)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.separator)
                )
                .accessibilityLabel("Practice dictation area")
        }
    }
}
