import AppKit
import GRDB
import SwiftUI

struct HistoryView: View {
    @State private var records: [TranscriptRecord] = []
    @State private var search = ""
    @State private var expanded: Set<Int64> = []
    @State private var confirmingClear = false
    @State private var retrying: Set<Int64> = []

    private var filtered: [TranscriptRecord] {
        guard !search.isEmpty else { return records }
        let needle = search.lowercased()
        return records.filter {
            $0.finalText.lowercased().contains(needle)
                || $0.rawText.lowercased().contains(needle)
                || ($0.appName?.lowercased().contains(needle) ?? false)
        }
    }

    /// Newest-first day groups.
    private var groups: [(day: Date, items: [TranscriptRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        // NavigationStack gives the window a toolbar for search + Clear All.
        NavigationStack {
            content
        }
        .onAppear(perform: load)
        .frame(minWidth: 640, minHeight: 400)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Transcripts Yet",
                    systemImage: "waveform",
                    description: Text("Hold Fn and speak — finished dictations appear here.")
                )
            } else {
                List {
                    ForEach(groups, id: \.day) { group in
                        Section(group.day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(group.items) { record in
                                HistoryRow(
                                    record: record,
                                    isExpanded: record.id.map { expanded.contains($0) } ?? false,
                                    isRetrying: record.id.map { retrying.contains($0) } ?? false,
                                    toggleExpanded: { toggleExpanded(record) },
                                    onDelete: { delete(record) },
                                    onRetry: { retry(record) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search transcripts")
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    confirmingClear = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(records.isEmpty)
            }
        }
        .confirmationDialog("Delete all transcripts?", isPresented: $confirmingClear) {
            Button("Delete All", role: .destructive) {
                try? AppDatabase.shared.queue.write { db in
                    try db.execute(sql: "DELETE FROM transcripts")
                }
                records = []
            }
        } message: {
            Text("This permanently removes every saved transcript. It cannot be undone.")
        }
    }

    private func load() {
        records = (try? AppDatabase.shared.queue.read { db in
            try TranscriptRecord.order(Column("created_at").desc).fetchAll(db)
        }) ?? []
    }

    private func toggleExpanded(_ record: TranscriptRecord) {
        guard let id = record.id else { return }
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func delete(_ record: TranscriptRecord) {
        _ = try? AppDatabase.shared.queue.write { db in try record.delete(db) }
        if let path = record.audioPath { try? FileManager.default.removeItem(atPath: path) }
        records.removeAll { $0.id == record.id }
    }

    /// Re-run ASR on the retained audio of a failed dictation; result goes to the clipboard.
    private func retry(_ record: TranscriptRecord) {
        guard let id = record.id, let path = record.audioPath, !retrying.contains(id) else { return }
        retrying.insert(id)
        Task {
            defer {
                retrying.remove(id)
                load()
            }
            do {
                let text = try await FileTranscriber.transcribe(
                    url: URL(fileURLWithPath: path), localeID: Prefs.languageID
                )
                guard !text.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                try? await AppDatabase.shared.queue.write { db in
                    try db.execute(
                        sql: """
                        UPDATE transcripts SET raw_text = ?, final_text = ?, error_code = NULL,
                            insertion_status = 'copied', audio_path = NULL WHERE id = ?
                        """,
                        arguments: [text, text, id]
                    )
                }
                try? FileManager.default.removeItem(atPath: path)
            } catch {
                log.error("Retry transcription failed: \(error.localizedDescription)")
            }
        }
    }
}

private struct HistoryRow: View {
    let record: TranscriptRecord
    let isExpanded: Bool
    let isRetrying: Bool
    let toggleExpanded: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void

    private var isFailed: Bool {
        record.errorCode != nil && record.audioPath != nil
    }

    private var displayText: String {
        if record.isSensitive { return "•••" }
        if isFailed { return "Transcription failed — audio saved" }
        return record.finalText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayText)
                    .lineLimit(isExpanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                if let app = record.appName { badge(app, systemImage: "app") }
                if let engine = record.asrEngine { badge(engine, systemImage: "waveform") }
                if let latency = record.asrLatencyMs { badge("\(latency) ms", systemImage: "timer") }
                if isFailed {
                    if isRetrying {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button {
                            onRetry()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.mini)
                        .help("Transcribe the saved audio again; result is copied to the clipboard")
                    }
                }
                Spacer()
                if isExpanded {
                    Button("Copy Final") { copy(record.finalText) }
                        .controlSize(.mini)
                    Button("Copy Raw") { copy(record.rawText) }
                        .controlSize(.mini)
                    Button(role: .destructive, action: onDelete) { Text("Delete") }
                        .controlSize(.mini)
                }
            }

            if isExpanded, !record.isSensitive {
                VStack(alignment: .leading, spacing: 8) {
                    stage("Raw", text: record.rawText)
                    if let processed = record.ruleProcessedText, processed != record.rawText {
                        stage("Rules Applied", text: processed)
                    }
                    if record.finalText != record.rawText {
                        stage("Final", text: record.finalText)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // Separate onTapGesture(count: 2) + onTapGesture don't compose: a double-click would
        // expand-then-collapse AND copy. highPriorityGesture makes the double-click win.
        .highPriorityGesture(TapGesture(count: 2).onEnded { copy(record.finalText) })
        .onTapGesture { toggleExpanded() }
        .contextMenu {
            Button("Copy Final Text") { copy(record.finalText) }
            Button("Copy Raw Transcript") { copy(record.rawText) }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .help("Double-click to copy")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcript: \(displayText)")
    }

    private func badge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary.opacity(0.5)))
    }

    private func stage(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .textSelection(.enabled)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
