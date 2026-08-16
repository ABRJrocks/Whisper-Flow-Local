import GRDB
import SwiftUI

struct PersonalizationSettings: View {
    private enum Section: String, CaseIterable {
        case dictionary = "Dictionary"
        case snippets = "Snippets"
        case styles = "Styles"
    }

    @State private var section: Section = .dictionary

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            switch section {
            case .dictionary: DictionaryEditor()
            case .snippets: SnippetsEditor()
            case .styles: StylesEditor()
            }

            if section == .dictionary {
                Toggle("Learn new spellings from my corrections automatically", isOn: Bindable(PrefsModel.shared).autoLearnEnabled)
                    .padding([.horizontal, .bottom])
                    .help("When you correct a dictated word in place, FlowLocal notices and adds the replacement here after seeing it twice. Everything stays on this Mac.")
            }
        }
    }
}

// MARK: - Dictionary

private struct DictionaryEditor: View {
    @State private var entries: [DictionaryEntryRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach($entries) { $entry in
                    HStack(spacing: 8) {
                        TextField("Spoken form", text: Binding(
                            get: { entry.spokenForm ?? "" },
                            set: { entry.spokenForm = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Spoken form")

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        TextField("Written form", text: $entry.writtenForm)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Written form")

                        Toggle("Whole word", isOn: $entry.wholeWord)
                            .toggleStyle(.checkbox)
                            .help("Only replace whole-word matches")
                        Toggle("Match case", isOn: $entry.caseSensitive)
                            .toggleStyle(.checkbox)
                            .help("Case-sensitive matching")

                        Button {
                            delete(entry)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete dictionary entry")
                    }
                    .onChange(of: entry) { _, updated in save(updated) }
                }
            }
            .listStyle(.inset)

            HStack {
                Button {
                    let entry = DictionaryEntryRecord.new(spoken: "", written: "")
                    entries.append(entry)
                    save(entry)
                } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                Spacer()
                Text("Replacements are applied to every transcript before AI cleanup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    private func load() {
        entries = (try? AppDatabase.shared.queue.read { db in
            try DictionaryEntryRecord.order(Column("created_at")).fetchAll(db)
        }) ?? []
    }

    private func save(_ entry: DictionaryEntryRecord) {
        var entry = entry
        entry.updatedAt = Date()
        try? AppDatabase.shared.queue.write { db in try entry.save(db) }
    }

    private func delete(_ entry: DictionaryEntryRecord) {
        _ = try? AppDatabase.shared.queue.write { db in try entry.delete(db) }
        entries.removeAll { $0.id == entry.id }
    }
}

// MARK: - Snippets

private struct SnippetsEditor: View {
    @State private var snippets: [SnippetRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach($snippets) { $snippet in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Trigger phrase", text: $snippet.trigger)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 220)
                                .accessibilityLabel("Snippet trigger")
                            Spacer()
                            Toggle("Sensitive", isOn: $snippet.isSensitive)
                                .toggleStyle(.checkbox)
                                .help("Hide the expansion in history")
                            Toggle("Inline", isOn: $snippet.allowInline)
                                .toggleStyle(.checkbox)
                                .help("Expand when spoken mid-sentence")
                            Button {
                                delete(snippet)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete snippet")
                        }
                        TextEditor(text: $snippet.expansion)
                            .font(.system(size: 12))
                            .frame(height: 54)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                            .accessibilityLabel("Snippet expansion text")
                    }
                    .padding(.vertical, 4)
                    .onChange(of: snippet) { _, updated in save(updated) }
                }
            }
            .listStyle(.inset)

            HStack {
                Button {
                    let snippet = SnippetRecord.new(trigger: "", expansion: "")
                    snippets.append(snippet)
                    save(snippet)
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
                Spacer()
                Text("Say the trigger phrase while dictating to insert the expansion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    private func load() {
        snippets = (try? AppDatabase.shared.queue.read { db in
            try SnippetRecord.order(Column("created_at")).fetchAll(db)
        }) ?? []
    }

    private func save(_ snippet: SnippetRecord) {
        var snippet = snippet
        snippet.updatedAt = Date()
        try? AppDatabase.shared.queue.write { db in try snippet.save(db) }
    }

    private func delete(_ snippet: SnippetRecord) {
        _ = try? AppDatabase.shared.queue.write { db in try snippet.delete(db) }
        snippets.removeAll { $0.id == snippet.id }
    }
}

// MARK: - Styles

private struct StylesEditor: View {
    @State private var styles: [StyleRecord] = []

    var body: some View {
        List {
            ForEach($styles) { $style in
                VStack(alignment: .leading, spacing: 8) {
                    Text(style.name)
                        .font(.headline)
                    HStack {
                        Text("Formality").frame(width: 70, alignment: .leading)
                        Slider(value: $style.formality, in: 0...1)
                            .accessibilityLabel("Formality for \(style.name)")
                        Text("Concision").frame(width: 70, alignment: .leading)
                        Slider(value: $style.concision, in: 0...1)
                            .accessibilityLabel("Concision for \(style.name)")
                        Toggle("Emoji", isOn: $style.emojiAllowed)
                            .toggleStyle(.checkbox)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    TextField("Custom instructions (optional)", text: $style.customInstructions, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .accessibilityLabel("Custom instructions for \(style.name)")
                }
                .padding(.vertical, 6)
                .onChange(of: style) { _, updated in
                    try? AppDatabase.shared.queue.write { db in try updated.save(db) }
                }
            }
        }
        .listStyle(.inset)
        .onAppear(perform: load)
    }

    private func load() {
        styles = (try? AppDatabase.shared.queue.read { db in
            try StyleRecord.fetchAll(db)
        }) ?? []
        if styles.isEmpty {
            styles = StyleRecord.defaults
            try? AppDatabase.shared.queue.write { db in
                for style in StyleRecord.defaults { try style.save(db) }
            }
        }
    }
}
