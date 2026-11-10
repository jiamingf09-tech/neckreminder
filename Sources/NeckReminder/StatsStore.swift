import Foundation
import NeckReminderCore

/// Daily usage and relax totals. One record per day, kept for as long as the app is installed.
/// A day is about 200 bytes, so ten years is roughly half a megabyte.
/// Stored in ~/Library/Application Support/NeckReminder/daily-stats.json.
/// Older builds kept the same JSON in UserDefaults for 30 days; the first launch copies it across.
@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var today: DayStats
    @Published private(set) var history: [String: DayStats]

    private let defaults: UserDefaults
    private let legacyKey = "dailyStats"
    private let fileURL: URL
    private var dirtyCount = 0
    private var dropLegacyDefaults = false

    private func hasActivity(_ day: DayStats) -> Bool {
        day.activeSeconds > 0 || day.relaxSeconds > 0 || day.reminders > 0
            || day.relaxSessions > 0 || day.breaks > 0 || day.longestStretch > 0
    }

    init(defaults: UserDefaults = .standard, fileURL: URL? = nil) {
        self.defaults = defaults
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let dir = base.appendingPathComponent("NeckReminder", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("daily-stats.json")
        }

        var loaded: [String: DayStats] = [:]
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data) {
            loaded = decoded
        }
        if let data = defaults.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode([String: DayStats].self, from: data) {
            for (day, stats) in legacy where loaded[day] == nil {
                loaded[day] = stats
            }
            dropLegacyDefaults = true
        }
        let todayKey = DayKey.string(for: Date())
        history = loaded
        today = loaded[todayKey] ?? DayStats(day: todayKey)
        if dropLegacyDefaults { save() }
    }

    func update(_ change: (inout DayStats) -> Void) {
        let key = DayKey.string(for: Date())
        if today.day != key {
            if hasActivity(today) || history[today.day] != nil {
                history[today.day] = today
            }
            today = history[key] ?? DayStats(day: key)
        }
        change(&today)
        history[today.day] = today
        dirtyCount += 1
        if dirtyCount >= 12 { save() }
    }

    /// Last `n` days, oldest first, including today. Missing days are zeros.
    func lastDays(_ n: Int) -> [DayStats] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return (0..<n).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: start) ?? start
            let k = DayKey.string(for: d)
            return k == today.day ? today : (history[k] ?? DayStats(day: k))
        }
    }

    /// Every day that has been recorded, oldest first, with today's latest numbers.
    /// A brand-new day with no activity yet is left out, so the count stays at zero
    /// until something is actually stored.
    func allDays() -> [DayStats] {
        var days = history
        if hasActivity(today) || days[today.day] != nil {
            days[today.day] = today
        }
        return days.values.sorted { $0.day < $1.day }
    }

    /// Flush today's numbers and return every stored day, oldest first.
    func daysForExport() -> [DayStats] {
        save()
        return history.values.sorted { $0.day < $1.day }
    }

    func save() {
        dirtyCount = 0
        // An unused day is not a record. Writing it would add a row every time the file is saved.
        if hasActivity(today) || history[today.day] != nil {
            history[today.day] = today
        }
        guard let data = try? JSONEncoder().encode(history) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            if dropLegacyDefaults {
                defaults.removeObject(forKey: legacyKey)
                dropLegacyDefaults = false
            }
        } catch {
            // Leave the UserDefaults copy in place until a later save succeeds.
        }
    }
}
