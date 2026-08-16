import GRDB
import SwiftUI

struct PrivacySettings: View {
    @State private var prefs = PrefsModel.shared
    @State private var confirmingClear = false
    @State private var storageBytes: Int64 = 0

    var body: some View {
        Form {
            Section("Context") {
                Toggle("Context awareness", isOn: $prefs.contextAwarenessEnabled)
                Text("Adapts tone and formatting to the app you're dictating into. The app name and nearby text never leave this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Toggle("Save transcript history", isOn: $prefs.historyEnabled)
                Picker("Keep transcripts", selection: $prefs.historyRetentionDays) {
                    Text("Forever").tag(0)
                    Text("24 hours").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                LabeledContent("Storage used", value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                Button("Clear All History…", role: .destructive) {
                    confirmingClear = true
                }
                .confirmationDialog("Delete all transcripts?", isPresented: $confirmingClear) {
                    Button("Delete All", role: .destructive) {
                        try? AppDatabase.shared.queue.write { db in
                            try db.execute(sql: "DELETE FROM transcripts")
                        }
                        refreshStorage()
                    }
                } message: {
                    Text("This permanently removes every saved transcript from this Mac. It cannot be undone.")
                }
            }

            Section("Your data stays here") {
                Text("FlowLocal is local-first: audio, transcripts, and AI processing never leave this Mac. There is no account, no cloud, and no telemetry. Everything lives in a single database file under Application Support that you can delete at any time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshStorage)
    }

    private func refreshStorage() {
        let dir = AppDatabase.supportDirectory
        var total: Int64 = 0
        if let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in files {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        storageBytes = total
    }
}
