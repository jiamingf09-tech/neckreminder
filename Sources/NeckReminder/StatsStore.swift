import Foundation
import NeckReminderCore

/// Daily statistics, kept for the last few weeks in UserDefaults.
@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var today: DayStats
    @Published private(set) var history: [String: DayStats]

    private let defaults: UserDefaults
    private let key = "dailyStats"
    private let keepDays = 30
    private var dirtyCount = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [String: DayStats] = [:]
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data) {
            loaded = decoded
        }
        let todayKey = DayKey.string(for: Date())
        history = loaded
        today = loaded[todayKey] ?? DayStats(day: todayKey)
    }

    func update(_ change: (inout DayStats) -> Void) {
        let key = DayKey.string(for: Date())
        if today.day != key {
            history[today.day] = today
            today = history[key] ?? DayStats(day: key)
        }
        change(&today)
        history[today.day] = today
        dirtyCount += 1
        if dirtyCount >= 12 { save() }
    }

    /// Last `n` days, oldest first, including today.
    func lastDays(_ n: Int) -> [DayStats] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return (0..<n).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: start) ?? start
            let k = DayKey.string(for: d)
            return k == today.day ? today : (history[k] ?? DayStats(day: k))
        }
    }

    func save() {
        dirtyCount = 0
        history[today.day] = today
        let keep = Set(lastDays(keepDays).map(\.day))
        let trimmed = history.filter { keep.contains($0.key) }
        history = trimmed
        if let data = try? JSONEncoder().encode(trimmed) {
            defaults.set(data, forKey: key)
        }
    }
}
