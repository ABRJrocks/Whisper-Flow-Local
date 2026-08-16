import AppKit
import Foundation

/// Global shortcut detection via NSEvent global monitors (requires Accessibility).
///
/// Chords:
///   - Dictation push-to-talk: hold Fn, or hold Ctrl+Opt
///   - Command Mode: hold Ctrl+Opt+Cmd
///   - Hands-free: double-tap the dictation chord
///   - Esc: cancel; any other key while holding the dictation chord cancels (accidental combo)
@MainActor
final class HotkeyService {
    var onHoldBegin: (() -> Void)?
    var onHoldEnd: ((TimeInterval) -> Void)?
    /// Chord upgraded mid-hold (Ctrl+Opt → +Cmd): discard the fragment, don't transcribe it.
    var onHoldCancel: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    var onCommandBegin: (() -> Void)?
    var onCommandEnd: ((TimeInterval) -> Void)?
    var onEscape: (() -> Void)?
    var onKeyInterrupt: (() -> Void)?

    private enum Chord { case none, dictation, command }
    private var activeChord: Chord = .none
    private var chordStart = Date.distantPast
    private var lastTapEnd = Date.distantPast

    private let tapMaxDuration: TimeInterval = 0.35
    private let doubleTapWindow: TimeInterval = 0.5

    private var monitors: [Any] = []

    func start() {
        // Global monitors never see events sent to our own app — without the local pair,
        // hotkeys go dead whenever FlowLocal is frontmost (e.g. dictating into the Scratchpad).
        let flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            Task { @MainActor in self?.handleFlags(flags) }
        }
        let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            Task { @MainActor in self?.handleKeyDown(keyCode: keyCode) }
        }
        let localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            Task { @MainActor in self?.handleFlags(flags) }
            return event
        }
        let localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            Task { @MainActor in self?.handleKeyDown(keyCode: keyCode) }
            return event
        }
        monitors = [flagsMonitor, keyMonitor, localFlagsMonitor, localKeyMonitor].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    private func desiredChord(for flags: NSEvent.ModifierFlags) -> Chord {
        let ctrl = flags.contains(.control)
        let opt = flags.contains(.option)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        let fn = flags.contains(.function)

        if ctrl && opt && cmd && !shift { return .command }
        if fn && !ctrl && !opt && !cmd { return .dictation }
        if ctrl && opt && !cmd && !shift { return .dictation }
        return .none
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let desired = desiredChord(for: flags)
        guard desired != activeChord else { return }

        let duration = Date().timeIntervalSince(chordStart)

        // Chord-to-chord transitions are the user forming/releasing Ctrl+Opt+Cmd one key at
        // a time — not a tap cycle. Never transcribe the fragment or count it as a tap.
        if activeChord == .dictation, desired == .command {
            onHoldCancel?()
            activeChord = .command
            chordStart = Date()
            onCommandBegin?()
            return
        }
        if activeChord == .command, desired == .dictation {
            onCommandEnd?(duration)
            activeChord = .none // releasing Cmd first must not start a stray dictation
            return
        }

        // End the current chord
        switch activeChord {
        case .dictation:
            onHoldEnd?(duration)
            if duration < tapMaxDuration {
                if Date().timeIntervalSince(lastTapEnd) < doubleTapWindow {
                    lastTapEnd = .distantPast
                    onDoubleTap?()
                } else {
                    lastTapEnd = Date()
                }
            }
        case .command:
            onCommandEnd?(duration)
        case .none:
            break
        }

        // Begin the new chord
        activeChord = desired
        chordStart = Date()
        switch desired {
        case .dictation: onHoldBegin?()
        case .command: onCommandBegin?()
        case .none: break
        }
    }

    private func handleKeyDown(keyCode: UInt16) {
        if keyCode == 53 { // Esc
            onEscape?()
            return
        }
        if activeChord != .none {
            onKeyInterrupt?()
        }
    }
}
