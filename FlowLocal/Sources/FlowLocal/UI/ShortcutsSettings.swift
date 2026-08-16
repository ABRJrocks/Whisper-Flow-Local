import SwiftUI

/// Read-only list of the fixed key bindings, presented with key-cap styling.
struct ShortcutsSettings: View {
    private static let bindings: [(action: String, detail: String, keys: [String])] = [
        ("Push-to-talk", "Hold to dictate, release to insert", ["fn"]),
        ("Push-to-talk (alternate)", "Same, for keyboards without Fn", ["⌃", "⌥"]),
        ("Hands-free", "Double-tap to start, tap Stop or Esc to end", ["fn", "fn"]),
        ("Command Mode", "Hold and speak an edit instruction", ["⌃", "⌥", "⌘"]),
        ("Cancel", "Discard the current dictation", ["esc"]),
        ("Paste Last Transcript", "From the menu bar icon", ["menu"]),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Self.bindings, id: \.action) { binding in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.action)
                            Text(binding.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(Array(binding.keys.enumerated()), id: \.offset) { _, key in
                                KeyCap(key)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(binding.action): \(binding.keys.joined(separator: " ")). \(binding.detail)")
                }
            } footer: {
                Text("Shortcuts are fixed in this version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyCap: View {
    let label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minWidth: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            )
    }
}
