import AppKit
import ApplicationServices
import Foundation

enum InsertionOutcome {
    case pasted
    case leftOnClipboard(reason: String)
}

/// Reads the focused UI element via Accessibility. All calls bounded and failure-tolerant.
enum FocusReader {
    struct FocusInfo {
        var hasFocusedElement: Bool
        var hasEditableFocus: Bool
        var isSecure: Bool
        var textBeforeCursor: String?
        var selectedText: String?
    }

    /// The focused UI element itself (for later re-reads, e.g. correction learning).
    /// Queries the frontmost application's AX element — on macOS 26 the system-wide
    /// focused-element query fails with cannotComplete (-25204) even when trusted.
    static func focusedElement() -> AXUIElement? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
               let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
            {
                return unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
            }
        }
        // Fallback: the classic system-wide query.
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(focused as AnyObject, to: AXUIElement.self)
    }

    static func currentFocus() -> FocusInfo {
        guard let element = focusedElement() else {
            return FocusInfo(hasFocusedElement: false, hasEditableFocus: false, isSecure: false, textBeforeCursor: nil, selectedText: nil)
        }

        let role = stringAttribute(element, kAXRoleAttribute)
        let subrole = stringAttribute(element, kAXSubroleAttribute)

        let isSecure = subrole == "AXSecureTextField"
        let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        var editable = editableRoles.contains(role ?? "")
        // Web areas and custom editors often expose AXValue as settable instead of a text role.
        if !editable {
            var settable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
                editable = settable.boolValue
            }
        }

        var before: String?
        var selected: String?
        if editable && !isSecure {
            before = textBeforeCursor(element)
            var selRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selRef) == .success {
                selected = (selRef as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
        }
        return FocusInfo(hasFocusedElement: true, hasEditableFocus: editable, isSecure: isSecure, textBeforeCursor: before, selectedText: selected)
    }

    private static func textBeforeCursor(_ element: AXUIElement, limit: Int = 1000) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String
        else { return nil }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(rangeValue as AnyObject, to: AXValue.self), .cfRange, &range) else { return nil }
        let scalars = Array(value.unicodeScalars)
        let cursor = min(max(0, range.location), scalars.count)
        let start = max(0, cursor - limit)
        return String(String.UnicodeScalarView(scalars[start..<cursor]))
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}

/// Clipboard-transaction paste: snapshot clipboard, write text, synthesize Cmd+V,
/// restore snapshot only if we still own the pasteboard. On any doubt, the dictated
/// text stays on the clipboard — text is never lost.
@MainActor
final class PasteService {
    private(set) var lastText: String?

    /// `beganEditable`: the focus state captured when dictation STARTED. Some apps
    /// (web areas, custom editors) intermittently fail the AX editability probe at
    /// insert time even though the caret never moved — in that case paste optimistically:
    /// Cmd+V into a non-editable target is a no-op and the text stays on the clipboard.
    func insert(_ text: String, beganEditable: Bool = false) -> InsertionOutcome {
        lastText = text
        // Without Accessibility trust, focus reading AND the synthesized Cmd+V both fail
        // silently — report the real cause instead of "no editable field".
        guard AXIsProcessTrusted() else {
            copyOnly(text)
            return .leftOnClipboard(reason: "Grant Accessibility in System Settings — text copied")
        }
        let focus = FocusReader.currentFocus()

        if focus.isSecure {
            copyOnly(text)
            return .leftOnClipboard(reason: "Secure field — copied instead of pasting")
        }
        // Electron/Chromium apps (Cursor, Slack, Chrome, …) don't expose an editable AX
        // role until an assistive client wakes their tree, so the editability probe fails
        // even though Cmd+V lands fine. Paste optimistically whenever ANYTHING has focus;
        // only give up when there is no focused element at all.
        let confirmed = focus.hasEditableFocus || beganEditable
        guard confirmed || focus.hasFocusedElement else {
            copyOnly(text)
            return .leftOnClipboard(reason: "No focused field — text copied")
        }

        let finalText = TextCleanup.joined(text, textBeforeCursor: focus.textBeforeCursor)
        let pasteboard = NSPasteboard.general
        let savedString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(finalText, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        synthesizeCmdV()

        // Restore the user's clipboard after the paste lands, only if untouched since.
        // In unconfirmed (optimistic) mode, keep the text on the clipboard instead —
        // if the paste was a no-op the dictation must not be lost.
        if confirmed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if pasteboard.changeCount == ourChangeCount, let savedString {
                    pasteboard.clearContents()
                    pasteboard.setString(savedString, forType: .string)
                }
            }
        }
        return .pasted
    }

    func copyOnly(_ text: String) {
        lastText = text
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func pasteLast() {
        guard let lastText else { return }
        _ = insert(lastText)
    }

    /// Safe text-editing keystrokes for Command Mode ("press enter" etc.).
    func sendKeystroke(_ name: String) {
        let keyCode: CGKeyCode
        switch name {
        case "enter": keyCode = 36
        case "tab": keyCode = 48
        case "backspace": keyCode = 51
        default: return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func synthesizeCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
