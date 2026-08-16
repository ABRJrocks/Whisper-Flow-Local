import AppKit
import SwiftUI

/// Single entry point for every app window. Each is a reused singleton NSWindow
/// so it works in an LSUIElement (.accessory) app.
@MainActor
enum AppWindows {
    private static var settingsWindow: NSWindow?
    private static var historyWindow: NSWindow?
    private static var scratchpadWindow: NSWindow?
    private static var onboardingWindow: NSWindow?
    private static var insightsWindow: NSWindow?

    static func showSettings() {
        present(&settingsWindow, title: "FlowLocal Settings", size: NSSize(width: 720, height: 560)) {
            SettingsRootView()
        }
    }

    static func showHistory() {
        present(&historyWindow, title: "History", size: NSSize(width: 760, height: 560)) {
            HistoryView()
        }
    }

    static func showScratchpad() {
        present(&scratchpadWindow, title: "Scratchpad", size: NSSize(width: 800, height: 560)) {
            ScratchpadView()
        }
    }

    static func showInsights() {
        present(&insightsWindow, title: "Insights", size: NSSize(width: 680, height: 520)) {
            InsightsView()
        }
    }

    static func showOnboardingIfNeeded() {
        guard !Prefs.firstRunCompleted else { return }
        showOnboarding()
    }

    static func showOnboarding() {
        present(&onboardingWindow, title: "Welcome to FlowLocal", size: NSSize(width: 640, height: 540),
                style: [.titled, .closable, .fullSizeContentView]) {
            OnboardingView { onboardingWindow?.close() }
        }
        onboardingWindow?.titlebarAppearsTransparent = true
        onboardingWindow?.titleVisibility = .hidden
    }

    private static func present<Content: View>(
        _ slot: inout NSWindow?,
        title: String,
        size: NSSize,
        style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable],
        @ViewBuilder content: () -> Content
    ) {
        // NSHostingController + toolbar bridging: a plain NSHostingView drops SwiftUI
        // .toolbar and .searchable chrome entirely (no NSToolbar to land in).
        let hosting = NSHostingController(rootView: content())
        hosting.sceneBridgingOptions = [.toolbars]

        if let window = slot {
            // Recreate the root view on every open so .onAppear loads fresh data.
            let frame = window.frame
            window.contentViewController = hosting
            window.setFrame(frame, display: false)
        } else {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: style,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = title
            window.contentViewController = hosting
            window.setContentSize(size)
            window.center()
            slot = window
        }
        NSApp.activate(ignoringOtherApps: true)
        slot?.makeKeyAndOrderFront(nil)
    }
}
