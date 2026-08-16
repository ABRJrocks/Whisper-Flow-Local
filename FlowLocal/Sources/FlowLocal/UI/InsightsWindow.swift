import Charts
import GRDB
import SwiftUI

/// Local dictation stats computed from the transcripts table. No new data is collected.
struct InsightsView: View {
    private struct DayWords: Identifiable {
        var id: Date { day }
        let day: Date
        let words: Int
    }

    private struct Stats {
        var totalWords = 0
        var sessions = 0
        var averageWPM = 0
        var streakDays = 0
        var topApps: [(name: String, sessions: Int)] = []
        var recentDays: [DayWords] = []
    }

    @State private var stats = Stats()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    statTile("Words dictated", "\(stats.totalWords.formatted())", "text.word.spacing")
                    statTile("Sessions", "\(stats.sessions.formatted())", "waveform")
                    statTile("Average speed", stats.averageWPM > 0 ? "\(stats.averageWPM) WPM" : "—", "speedometer")
                    statTile("Streak", stats.streakDays == 1 ? "1 day" : "\(stats.streakDays) days", "flame")
                }

                GroupBox("Words per day — last 14 days") {
                    if stats.recentDays.allSatisfy({ $0.words == 0 }) {
                        Text("Dictate something to see your activity here.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        Chart(stats.recentDays) { day in
                            BarMark(
                                x: .value("Day", day.day, unit: .day),
                                y: .value("Words", day.words)
                            )
                            .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 2)) {
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            }
                        }
                        .frame(minHeight: 160)
                        .padding(.top, 4)
                    }
                }

                GroupBox("Top apps") {
                    if stats.topApps.isEmpty {
                        Text("No sessions yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(stats.topApps, id: \.name) { app in
                                HStack {
                                    Text(app.name)
                                    Spacer()
                                    Text("\(app.sessions) session\(app.sessions == 1 ? "" : "s")")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 460)
        .onAppear(perform: load)
    }

    private func statTile(_ title: String, _ value: String, _ symbol: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() {
        struct Row: Decodable, FetchableRecord {
            var createdAt: Date
            var finalText: String
            var audioDurationMs: Int?
            var appName: String?

            enum CodingKeys: String, CodingKey {
                case createdAt = "created_at"
                case finalText = "final_text"
                case audioDurationMs = "audio_duration_ms"
                case appName = "app_name"
            }
        }
        let rows = (try? AppDatabase.shared.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT created_at, final_text, audio_duration_ms, app_name
                FROM transcripts WHERE session_type = 'dictation'
                """)
        }) ?? []

        var next = Stats()
        next.sessions = rows.count

        let calendar = Calendar.current
        var wordsByDay: [Date: Int] = [:]
        var appSessions: [String: Int] = [:]
        var speechMs = 0
        var speechWords = 0

        for row in rows {
            let words = row.finalText.split(whereSeparator: \.isWhitespace).count
            next.totalWords += words
            wordsByDay[calendar.startOfDay(for: row.createdAt), default: 0] += words
            if let name = row.appName { appSessions[name, default: 0] += 1 }
            if let ms = row.audioDurationMs, ms > 500 {
                speechMs += ms
                speechWords += words
            }
        }

        if speechMs > 0 {
            next.averageWPM = Int(Double(speechWords) / (Double(speechMs) / 60000))
        }
        next.topApps = appSessions.sorted { $0.value > $1.value }.prefix(5)
            .map { (name: $0.key, sessions: $0.value) }

        // Streak: consecutive days with activity, counting back from today or yesterday.
        var day = calendar.startOfDay(for: Date())
        if wordsByDay[day] == nil { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        while wordsByDay[day] != nil {
            next.streakDays += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }

        let today = calendar.startOfDay(for: Date())
        next.recentDays = (0..<14).reversed().compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayWords(day: d, words: wordsByDay[d] ?? 0)
        }
        stats = next
    }
}
