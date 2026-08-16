import AppKit
@preconcurrency import AVFoundation
import Foundation
import os

let log = Logger(subsystem: "com.local.flowlocal", category: "dictation")

/// Single authoritative state machine for dictation and Command Mode (spec §8.3).
@MainActor
final class DictationController {
    enum Mode: Equatable { case hold, handsFree, command }

    struct ActiveSession {
        let mode: Mode
        let startedAt: Date
        let language: String
        let engineID: String
        let asrSession: any ASRSession
        let appName: String?
        let bundleID: String?
        let appCategory: String
        let textBeforeCursor: String?
        let selectedText: String?
        let isSecureContext: Bool
        let hadEditableFocus: Bool
        let recoveryURL: URL?
        var lastVoiceAt: Date
    }

    enum State { case idle, recording, processing }

    private(set) var state: State = .idle
    private var session: ActiveSession?
    /// Bumped by begin() and cancel(); in-flight finish Tasks compare against it so a
    /// cancelled session can never paste or record after the fact.
    private var generation = 0
    var onStateChange: ((State) -> Void)?

    private let recorder = AudioRecorder()
    let panel = FlowPanelController()
    let pasteService = PasteService()
    private var silenceTimer: Timer?
    private var limitTimer: Timer?

    init() {
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.onStop = { [weak self] in self?.end() }
    }

    // MARK: - Session lifecycle

    func begin(mode: Mode) {
        guard case .idle = state else {
            log.info("Ignoring begin: busy")
            return
        }
        generation += 1

        let contextEnabled = Prefs.contextAwarenessEnabled
        let focus = FocusReader.currentFocus()
        let front = AppCategories.frontmostApp()
        let language = Prefs.languageID == "auto"
            ? "auto"
            : Locale(identifier: Prefs.languageID).language.languageCode?.identifier ?? "en"

        state = .recording
        onStateChange?(state)
        panel.show(.listening(handsFree: mode == .handsFree))
        playSound("Tink")

        Task {
            await self.startRecording(
                mode: mode,
                language: language,
                focus: focus,
                front: front,
                contextEnabled: contextEnabled
            )
        }
    }

    private func startRecording(
        mode: Mode,
        language: String,
        focus: FocusReader.FocusInfo,
        front: (name: String?, bundleID: String?),
        contextEnabled: Bool
    ) async {
        let locale = Locale(identifier: Prefs.languageID)
        guard let engine = await ASRRouter.shared.engine(for: locale) else {
            fail("No engine supports \(Prefs.languageID). Open Model Center.")
            return
        }
        do {
            // Start the mic FIRST and queue audio while the engine warms up — otherwise the
            // first 2–4 s of speech (engine/session setup) are silently lost.
            let relay = AudioRelay()
            let recoveryURL = Prefs.dictationRecoveryEnabled && mode != .command
                ? RecoveryStore.newFileURL() : nil
            try recorder.start(
                recordTo: recoveryURL,
                onBuffer: { buffer in relay.feed(buffer) },
                onLevel: { [weak self] level in
                    Task { @MainActor in self?.observeLevel(level) }
                }
            )

            if await !engine.isReady(locale: locale) {
                panel.transition(to: .processing(stage: "Preparing model…"))
                try await engine.prepare(locale: locale)
                panel.transition(to: .listening(handsFree: mode == .handsFree))
            }

            var partialHandler: (@Sendable (String) -> Void)?
            if Prefs.showPartialTranscript {
                partialHandler = { [weak self] partial in
                    Task { @MainActor in self?.panel.updatePartial(partial) }
                }
            }
            let asrSession = try await engine.startSession(locale: locale, onPartial: partialHandler)

            guard case .recording = state, session == nil else {
                recorder.stop()
                relay.drop()
                RecoveryStore.delete(recoveryURL)
                await asrSession.cancel()
                return
            }

            session = ActiveSession(
                mode: mode,
                startedAt: Date(),
                language: language,
                engineID: engine.id,
                asrSession: asrSession,
                appName: front.name,
                bundleID: front.bundleID,
                appCategory: AppCategories.category(for: front.bundleID),
                textBeforeCursor: contextEnabled && !focus.isSecure ? focus.textBeforeCursor : nil,
                selectedText: focus.selectedText,
                isSecureContext: focus.isSecure,
                hadEditableFocus: focus.hasEditableFocus,
                recoveryURL: recoveryURL,
                lastVoiceAt: Date()
            )

            relay.attach(asrSession) // flush queued warm-up audio, then feed live
            startTimers(mode: mode)
        } catch {
            recorder.stop()
            log.error("Failed to start dictation: \(error.localizedDescription)")
            fail("Couldn't start: \(error.localizedDescription)")
        }
    }

    func end() {
        guard case .recording = state else { return }
        guard let active = session else {
            // Engine still warming up; treat as cancel.
            cancel()
            return
        }
        let duration = Date().timeIntervalSince(active.startedAt)
        if active.mode != .handsFree, duration < Double(Prefs.minimumPressMs) / 1000 {
            cancel()
            return
        }

        state = .processing
        onStateChange?(state)
        stopTimers()
        recorder.stop()
        playSound("Pop")
        panel.transition(to: .processing(stage: "Transcribing…"))
        session = nil

        let gen = generation
        Task {
            let asrStart = Date()
            do {
                // ponytail: 90s ceiling; long hands-free sessions on slow machines may need tuning
                let result = try await withTimeout(seconds: 90) { try await active.asrSession.finish() }
                guard self.generation == gen else { return } // cancelled while transcribing
                let asrMs = Int(Date().timeIntervalSince(asrStart) * 1000)
                var raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                var pendingKeystroke: String?
                if Prefs.spokenCommandsEnabled, active.mode != .command {
                    let (stripped, keystroke) = TextCleanup.extractTrailingAction(raw)
                    raw = stripped
                    pendingKeystroke = keystroke
                }

                guard !raw.isEmpty else {
                    RecoveryStore.delete(active.recoveryURL)
                    self.panel.transition(to: .error(message: "No speech detected"))
                    self.panel.hide(after: 0.9)
                    self.toIdle()
                    return
                }

                if active.mode == .command {
                    await self.runCommand(instruction: raw, session: active, asrMs: asrMs, durationMs: Int(duration * 1000), gen: gen)
                    return
                }

                self.panel.transition(to: .processing(stage: "Polishing…"))
                let style = self.style(for: active.appCategory)
                let processed = await ProcessingPipeline(refiner: LLMManager.shared.refiner).process(
                    raw: raw,
                    language: active.language,
                    appCategory: active.appCategory,
                    style: style,
                    textBeforeCursor: active.textBeforeCursor,
                    secureContext: active.isSecureContext
                )

                guard self.generation == gen else { return } // cancelled while polishing
                self.panel.transition(to: .processing(stage: "Inserting…"))
                let outcome = self.pasteService.insert(processed.finalText, beganEditable: active.hadEditableFocus)

                let status: String
                switch outcome {
                case .pasted:
                    status = "pasted"
                    if let key = pendingKeystroke {
                        // After the synthesized Cmd+V has landed in the target app.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            self.pasteService.sendKeystroke(key)
                        }
                    }
                    if !processed.usedSensitiveSnippet, !active.isSecureContext {
                        CorrectionLearner.observeAfterPaste(inserted: processed.finalText)
                    }
                    self.panel.transition(to: .success)
                    self.panel.hide(after: 0.6)
                case .leftOnClipboard(let reason):
                    status = "copied"
                    self.panel.transition(to: .error(message: reason))
                    self.panel.hide(after: 2.5)
                }

                HistoryStore.record(
                    sessionType: "dictation",
                    language: active.language,
                    appName: active.appName,
                    bundleID: active.bundleID,
                    raw: raw,
                    ruleText: processed.ruleText,
                    finalText: processed.finalText,
                    asrEngine: active.engineID,
                    llmModel: processed.llmUsed ? LLMManager.shared.activeModelID : nil,
                    audioDurationMs: Int(duration * 1000),
                    asrLatencyMs: asrMs,
                    refinementLatencyMs: processed.refinementMs,
                    insertionStatus: status,
                    isSensitive: processed.usedSensitiveSnippet || active.isSecureContext
                )
                RecoveryStore.delete(active.recoveryURL)
                self.toIdle()
            } catch {
                log.error("Transcription failed: \(error.localizedDescription)")
                if let url = active.recoveryURL {
                    HistoryStore.record(
                        sessionType: "dictation",
                        language: active.language,
                        appName: active.appName,
                        bundleID: active.bundleID,
                        raw: "",
                        ruleText: nil,
                        finalText: "",
                        asrEngine: active.engineID,
                        llmModel: nil,
                        audioDurationMs: Int(duration * 1000),
                        asrLatencyMs: nil,
                        refinementLatencyMs: nil,
                        insertionStatus: "failed",
                        errorCode: "asr_failed",
                        audioPath: url.path
                    )
                    self.fail("Transcription failed — audio saved, retry from History")
                } else {
                    self.fail("Transcription failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancel() {
        generation += 1
        stopTimers()
        recorder.stop()
        let active = session
        session = nil
        RecoveryStore.delete(active?.recoveryURL)
        Task { await active?.asrSession.cancel() }
        panel.hide(after: 0)
        toIdle()
    }

    func toggleHandsFree() {
        switch state {
        case .recording:
            end()
        case .idle:
            begin(mode: .handsFree)
        case .processing:
            break
        }
    }

    /// Fn tap while hands-free recording stops it; hold while idle starts hold-mode.
    func holdBegan() {
        if case .recording = state, session?.mode == .handsFree {
            end()
            return
        }
        begin(mode: .hold)
    }

    func holdEnded(duration: TimeInterval) {
        guard session?.mode == .hold || (state == .recording && session == nil) else { return }
        end()
    }

    func commandEnded() {
        guard session?.mode == .command else { return }
        end()
    }

    func keyInterrupt() {
        guard case .recording = state, let mode = session?.mode else { return }
        if mode == .hold || mode == .command {
            cancel()
        }
    }

    func escapePressed() {
        if case .recording = state { cancel() }
    }

    // MARK: - Command Mode (spec §17)

    private func runCommand(instruction: String, session active: ActiveSession, asrMs: Int, durationMs: Int, gen: Int) async {
        guard let refiner = LLMManager.shared.refiner else {
            pasteService.copyOnly(instruction)
            panel.transition(to: .error(message: "Command Mode needs an AI model — instruction copied"))
            panel.hide(after: 2.5)
            toIdle()
            return
        }
        let selected = active.selectedText ?? ""
        if selected.unicodeScalars.count > 12_000 {
            panel.transition(to: .error(message: "Selection too large (12k character limit)"))
            panel.hide(after: 2.5)
            toIdle()
            return
        }
        panel.transition(to: .processing(stage: "Thinking…"))
        do {
            let action = try await withTimeout(seconds: 20) {
                try await refiner.command(
                    instruction: instruction,
                    selectedText: selected,
                    appCategory: active.appCategory,
                    language: active.language
                )
            }
            guard generation == gen else { return } // cancelled while thinking
            var status = "none"
            switch action.action {
            case .replace, .insert:
                let text = action.text
                guard !text.isEmpty else {
                    panel.transition(to: .error(message: "No result — nothing changed"))
                    panel.hide(after: 2.0)
                    toIdle()
                    return
                }
                // Guardrail: replacing a selection must not silently drop protected tokens
                // unless the user asked for a transformation that changes content.
                panel.transition(to: .processing(stage: "Inserting…"))
                let outcome = pasteService.insert(text, beganEditable: active.hadEditableFocus)
                status = { if case .pasted = outcome { return "pasted" } else { return "copied" } }()
                panel.transition(to: .success)
                panel.hide(after: 0.6)
            case .keystroke:
                if let key = action.keystroke {
                    pasteService.sendKeystroke(key)
                }
                status = "keystroke"
                panel.transition(to: .success)
                panel.hide(after: 0.5)
            case .none:
                panel.transition(to: .error(message: "Didn't catch an action"))
                panel.hide(after: 2.0)
            }
            HistoryStore.record(
                sessionType: "command",
                language: active.language,
                appName: active.appName,
                bundleID: active.bundleID,
                raw: instruction,
                ruleText: nil,
                finalText: action.text,
                selectedTextBefore: selected.isEmpty ? nil : selected,
                commandInstruction: instruction,
                asrEngine: active.engineID,
                llmModel: LLMManager.shared.activeModelID,
                audioDurationMs: durationMs,
                asrLatencyMs: asrMs,
                refinementLatencyMs: nil,
                insertionStatus: status
            )
            toIdle()
        } catch {
            log.error("Command Mode failed: \(error.localizedDescription)")
            fail("Command failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Timers, levels, helpers

    private func observeLevel(_ level: Float) {
        panel.updateLevel(level)
        if level > 0.05 { session?.lastVoiceAt = Date() }
    }

    private func startTimers(mode: Mode) {
        let limitMinutes = Prefs.sessionLimitMinutes
        if limitMinutes > 0 {
            limitTimer = Timer.scheduledTimer(withTimeInterval: Double(limitMinutes) * 60, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.end() }
            }
        }
        if mode == .handsFree, Prefs.silenceTimeoutSeconds > 0 {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, case .recording = self.state, let active = self.session else { return }
                    if Date().timeIntervalSince(active.lastVoiceAt) > Prefs.silenceTimeoutSeconds {
                        self.end()
                    }
                }
            }
        }
    }

    private func stopTimers() {
        silenceTimer?.invalidate()
        limitTimer?.invalidate()
        silenceTimer = nil
        limitTimer = nil
    }

    private func style(for category: String) -> StyleRecord? {
        let fromDB = try? AppDatabase.shared.queue.read { db in
            try StyleRecord.filter(sql: "category = ?", arguments: [category]).fetchOne(db)
        }
        return fromDB ?? StyleRecord.defaults.first { $0.category == category }
    }

    private func playSound(_ name: String) {
        guard Prefs.soundsEnabled else { return }
        NSSound(named: name)?.play()
    }

    private func fail(_ message: String) {
        stopTimers()
        recorder.stop()
        session = nil
        panel.transition(to: .error(message: message))
        panel.hide(after: 2.5)
        toIdle()
    }

    private func toIdle() {
        state = .idle
        onStateChange?(state)
    }
}
