import AppKit
import Foundation

/// Maps frontmost app bundle IDs to writing-style categories (spec §12.5).
enum AppCategories {
    static let map: [String: String] = [
        // Personal messaging
        "com.apple.MobileSMS": "personal_message",
        "net.whatsapp.WhatsApp": "personal_message",
        "ru.keepcoder.Telegram": "personal_message",
        "org.telegram.desktop": "personal_message",
        "org.whispersystems.signal-desktop": "personal_message",
        // Work messaging
        "com.tinyspeck.slackmacgap": "work_message",
        "com.microsoft.teams2": "work_message",
        "com.hnc.Discord": "work_message",
        // Email
        "com.apple.mail": "email",
        "com.readdle.smartemail-Mac": "email",
        "com.microsoft.Outlook": "email",
        // Documents
        "com.apple.Notes": "documents",
        "com.apple.TextEdit": "documents",
        "com.apple.iWork.Pages": "documents",
        "com.microsoft.Word": "documents",
        "notion.id": "documents",
        "md.obsidian": "documents",
        // Coding
        "com.apple.dt.Xcode": "coding",
        "com.todesktop.230313mzl4w4u92": "coding", // Cursor
        "com.microsoft.VSCode": "coding",
        // Terminal
        "com.apple.Terminal": "terminal",
        "com.googlecode.iterm2": "terminal",
        "dev.warp.Warp-Stable": "terminal",
        // AI chat
        "com.openai.chat": "ai_chat",
        "com.anthropic.claudefordesktop": "ai_chat",
    ]

    static func category(for bundleID: String?) -> String {
        guard let bundleID else { return "other" }
        return map[bundleID] ?? "other"
    }

    static func frontmostApp() -> (name: String?, bundleID: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }
}
