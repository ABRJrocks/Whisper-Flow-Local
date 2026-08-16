import AppKit
import ApplicationServices
@preconcurrency import AVFoundation
import Foundation

// MARK: - Headless self-check mode

let arguments = CommandLine.arguments
if let flagIndex = arguments.firstIndex(of: "--transcribe"), arguments.count > flagIndex + 1 {
    let file = arguments[flagIndex + 1]
    let localeID = arguments.firstIndex(of: "--locale").flatMap { i in
        arguments.count > i + 1 ? arguments[i + 1] : nil
    } ?? "en_US"
    let engineID = arguments.firstIndex(of: "--engine").flatMap { i in
        arguments.count > i + 1 ? arguments[i + 1] : nil
    } ?? "apple"
    exit(await SelfCheck.run(file: file, localeID: localeID, engineID: engineID))
}
if arguments.contains("--axcheck") {
    // Launched via `open --args --axcheck` so TCC attributes the check to the app bundle
    // itself. Writes one line and exits; used to diagnose Accessibility/focus issues.
    try? await Task.sleep(for: .seconds(2.5)) // let the previously-active app regain focus
    let trusted = AXIsProcessTrusted()
    let focus = FocusReader.currentFocus()
    let front = NSWorkspace.shared.frontmostApplication
    var focusedRef: CFTypeRef?
    let systemErr = AXUIElementCopyAttributeValue(
        AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focusedRef
    ).rawValue
    // App-scoped query: known to succeed where the system-wide one fails.
    var appErr: Int32 = -1
    var appRole = "?"
    if let pid = front?.processIdentifier {
        let appElement = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        appErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &ref).rawValue
        if appErr == 0, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            let element = unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            appRole = (roleRef as? String) ?? "nil"
        }
    }
    let report = "trusted=\(trusted) focused=\(focus.hasFocusedElement) editable=\(focus.hasEditableFocus) "
        + "secure=\(focus.isSecure) hasBefore=\(focus.textBeforeCursor != nil) "
        + "sysErr=\(systemErr) appErr=\(appErr) appRole=\(appRole) front=\(front?.localizedName ?? "?")(\(front?.bundleIdentifier ?? "?"))\n"
    try? report.write(toFile: "/tmp/flowlocal-axcheck.txt", atomically: true, encoding: .utf8)
    exit(0)
}
if let flagIndex = arguments.firstIndex(of: "--refine"), arguments.count > flagIndex + 1 {
    exit(await SelfCheck.runRefine(text: arguments[flagIndex + 1]))
}
if let flagIndex = arguments.firstIndex(of: "--command"), arguments.count > flagIndex + 2 {
    exit(await SelfCheck.runCommand(instruction: arguments[flagIndex + 1], selected: arguments[flagIndex + 2]))
}

// MARK: - Menu bar app

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = DictationController()
    private let hotkeys = HotkeyService()
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        controller.onStateChange = { [weak self] state in self?.reflect(state) }

        hotkeys.onHoldBegin = { [weak self] in self?.controller.holdBegan() }
        hotkeys.onHoldEnd = { [weak self] duration in self?.controller.holdEnded(duration: duration) }
        hotkeys.onHoldCancel = { [weak self] in self?.controller.cancel() }
        hotkeys.onDoubleTap = { [weak self] in
            if Prefs.doubleTapHandsFree { self?.controller.toggleHandsFree() }
        }
        hotkeys.onCommandBegin = { [weak self] in self?.controller.begin(mode: .command) }
        hotkeys.onCommandEnd = { [weak self] _ in self?.controller.commandEnded() }
        hotkeys.onEscape = { [weak self] in self?.controller.escapePressed() }
        hotkeys.onKeyInterrupt = { [weak self] in self?.controller.keyInterrupt() }
        hotkeys.start()

        RetentionService.cleanUp()
        AppWindows.showOnboardingIfNeeded()

        Task { await prepare() }
    }

    /// Double-clicking FlowLocal.app while it's running opens Settings — the only way in
    /// when the menu bar is too crowded for our status icon to be visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindows.showSettings()
        return true
    }

    private func prepare() async {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)

        let locale = Locale(identifier: Prefs.languageID)
        var modelReady: Bool
        if Prefs.languageID == "auto" {
            modelReady = await ASRRouter.shared.whisper.isReady(locale: locale)
        } else {
            modelReady = await SpeechModel.isInstalled(locale: locale)
        }
        if !modelReady, Prefs.languageID != "auto", await ASRRouter.shared.apple.supports(locale: locale) {
            statusMenuItem.title = "Downloading speech model…"
            do {
                try await SpeechModel.ensureInstalled(locale: locale)
                modelReady = true
            } catch {
                statusMenuItem.title = "Model download failed"
                log.error("Model install failed: \(error.localizedDescription)")
            }
        }

        // Warm the LLM refiner if one is active and memory allows.
        await LLMManager.shared.warmUpIfConfigured()

        if trusted && micGranted && modelReady {
            statusMenuItem.title = "Ready — hold Fn or Ctrl+Opt"
        } else if !trusted {
            statusMenuItem.title = "Grant Accessibility, then relaunch"
        } else if !micGranted {
            statusMenuItem.title = "Microphone access denied"
        } else {
            statusMenuItem.title = "Install a model in Model Center"
        }
    }

    private func setUpStatusItem() {
        // A saved position can land the icon behind the notch, where macOS silently hides
        // it. Always claim a fresh rightmost slot instead of restoring a stale position.
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position Item-0")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "FlowLocal")

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Start Hands-Free Dictation", action: #selector(startHandsFree), keyEquivalent: "")
        menu.addItem(withTitle: "Paste Last Transcript", action: #selector(pasteLast), keyEquivalent: "v")
        menu.addItem(withTitle: "Copy Last Transcript", action: #selector(copyLast), keyEquivalent: "c")
        menu.addItem(.separator())

        let languageMenu = NSMenu()
        for (id, name) in AppLanguages.all {
            let item = NSMenuItem(title: name, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = self
            item.state = Prefs.languageID == id ? .on : .off
            languageMenu.addItem(item)
        }
        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        menu.setSubmenu(languageMenu, for: languageItem)
        menu.addItem(languageItem)

        menu.addItem(withTitle: "History…", action: #selector(showHistory), keyEquivalent: "")
        menu.addItem(withTitle: "Insights…", action: #selector(showInsights), keyEquivalent: "")
        menu.addItem(withTitle: "Scratchpad…", action: #selector(showScratchpad), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FlowLocal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Quit must keep a nil target so the responder chain reaches NSApp; an explicit
        // non-responding target makes menu validation disable the item.
        menu.items.forEach {
            if $0.action != nil, $0.action != #selector(NSApplication.terminate(_:)) {
                $0.target = $0.target ?? self
            }
        }
        statusItem.menu = menu
    }

    private func reflect(_ state: DictationController.State) {
        let symbol: String
        switch state {
        case .idle: symbol = "mic.fill"
        case .recording: symbol = "waveform"
        case .processing: symbol = "hourglass"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FlowLocal")
    }

    @objc private func startHandsFree() { controller.toggleHandsFree() }
    @objc private func copyLast() {
        if let text = controller.pasteService.lastText { controller.pasteService.copyOnly(text) }
    }
    @objc private func pasteLast() { controller.pasteService.pasteLast() }
    @objc private func showHistory() { AppWindows.showHistory() }
    @objc private func showInsights() { AppWindows.showInsights() }
    @objc private func showScratchpad() { AppWindows.showScratchpad() }
    @objc private func showSettings() { AppWindows.showSettings() }
    @objc private func pickLanguage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        PrefsModel.shared.languageID = id // writes Prefs and keeps the Settings window in sync
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? String) == id ? .on : .off }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
