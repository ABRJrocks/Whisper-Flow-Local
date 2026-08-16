import GRDB
import SwiftUI

/// Local notes: sidebar of notes (pinned first), TextEditor detail with debounced autosave.
struct ScratchpadView: View {
    @State private var notes: [NoteRecord] = []
    @State private var selection: String?
    @State private var draft = ""
    @State private var search = ""
    @State private var saveTask: Task<Void, Never>?
    /// Pending debounced edit, captured with its note ID so a selection change can never
    /// flush the new note's (already reset) draft into the old note.
    @State private var pending: (noteID: String, content: String)?
    /// Content at the time of the last note_versions row, per note — versions are cut on >40 char delta.
    @State private var lastVersionedContent: [String: String] = [:]

    private var filteredNotes: [NoteRecord] {
        let base = search.isEmpty
            ? notes
            : notes.filter { $0.content.lowercased().contains(search.lowercased()) }
        return base.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filteredNotes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if note.pinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Pinned")
                            }
                            Text(note.title.isEmpty ? "New Note" : note.title)
                                .lineLimit(1)
                        }
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(note.id)
                    .contextMenu {
                        Button(note.pinned ? "Unpin" : "Pin") { togglePin(note) }
                        Button("Delete", role: .destructive) { delete(note) }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search notes")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem {
                    Button {
                        newNote()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
        } detail: {
            if selection != nil {
                TextEditor(text: $draft)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .accessibilityLabel("Note content")
                    .onChange(of: draft) { _, newValue in
                        scheduleAutosave(content: newValue)
                    }
            } else {
                ContentUnavailableView {
                    Label("No Note Selected", systemImage: "note.text")
                } description: {
                    Text("Select a note or create a new one.")
                } actions: {
                    Button("New Note", action: newNote)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: flushPending)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            flushPending()
        }
        .onChange(of: selection) { _, new in
            flushPending()
            draft = notes.first { $0.id == new }?.content ?? ""
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    // MARK: - Data

    private func load() {
        notes = (try? AppDatabase.shared.queue.read { db in
            try NoteRecord.fetchAll(db)
        }) ?? []
        if selection == nil { selection = filteredNotes.first?.id }
        draft = notes.first { $0.id == selection }?.content ?? ""
    }

    private func newNote() {
        let note = NoteRecord.new()
        try? AppDatabase.shared.queue.write { db in try note.save(db) }
        notes.append(note)
        selection = note.id
        draft = ""
    }

    private func delete(_ note: NoteRecord) {
        _ = try? AppDatabase.shared.queue.write { db in try note.delete(db) }
        notes.removeAll { $0.id == note.id }
        if selection == note.id {
            selection = filteredNotes.first?.id
            draft = notes.first { $0.id == selection }?.content ?? ""
        }
    }

    private func togglePin(_ note: NoteRecord) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].pinned.toggle()
        let updated = notes[index]
        try? AppDatabase.shared.queue.write { db in try updated.save(db) }
    }

    // MARK: - Autosave (~1s debounce)

    private func scheduleAutosave(content: String) {
        guard let id = selection else { return }
        pending = (id, content)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            flushPending()
        }
    }

    /// Persist the captured pending edit (if any). Idempotent; safe from any call site.
    private func flushPending() {
        saveTask?.cancel()
        guard let pending else { return }
        persist(noteID: pending.noteID, content: pending.content)
        self.pending = nil
    }

    private func persist(noteID: String, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        guard notes[index].content != content else { return }

        notes[index].content = content
        notes[index].title = String(
            content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                .first?.prefix(80) ?? ""
        )
        notes[index].updatedAt = Date()
        let note = notes[index]

        let baseline = lastVersionedContent[noteID] ?? ""
        let significant = abs(content.count - baseline.count) > 40
        if significant { lastVersionedContent[noteID] = content }

        try? AppDatabase.shared.queue.write { db in
            try note.save(db)
            if significant {
                try db.execute(
                    sql: "INSERT INTO note_versions (note_id, content, created_at) VALUES (?, ?, ?)",
                    arguments: [note.id, content, Date()]
                )
            }
        }
    }
}
