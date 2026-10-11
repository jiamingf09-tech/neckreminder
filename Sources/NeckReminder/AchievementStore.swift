import Foundation
import NeckReminderCore

/// Tracks completed relax sessions, XP, levels and unlocked achievements.
/// Stored in ~/Library/Application Support/NeckReminder/achievements.json.
@MainActor
final class AchievementStore: ObservableObject {
    struct SessionResult: Equatable {
        var xp: Int
        var timely: Bool
        var streak: Int
        var newAchievements: [Achievement]
        var leveledUpTo: Int?
    }

    @Published private(set) var log = ActivityLog()
    @Published private(set) var unlocked: [String: Date] = [:]
    /// Result of the most recent completed session (shown on the "done" screen).
    @Published private(set) var lastResult: SessionResult?

    private struct Stored: Codable {
        var log: ActivityLog
        var unlocked: [String: Date]
    }

    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("NeckReminder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("achievements.json")
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            log = stored.log
            unlocked = stored.unlocked
        }
    }

    var level: Int { Achievements.level(forXP: log.xp) }

    /// A completed session. Returns what to celebrate.
    @discardableResult
    func recordSession(activeSeconds: TimeInterval, routineSeconds: Int, timely: Bool,
                       content: ContentStore, now: Date = Date()) -> SessionResult {
        let levelBefore = level
        let gained = Achievements.xp(activeSeconds: activeSeconds, timely: timely)
        log.completedSessions += 1
        log.relaxSeconds += activeSeconds
        if timely { log.timelyResponses += 1 }
        log.sessionDays[DayKey.string(for: now), default: 0] += 1
        if routineSeconds >= 30 * 60 { log.longSessions += 1 }
        if Calendar.current.component(.hour, from: now) < 10 { log.morningSessions += 1 }
        log.xp += gained

        let fresh = unlockNew(content: content, now: now)
        let result = SessionResult(xp: gained + fresh.count * Achievements.xpPerAchievement,
                                   timely: timely,
                                   streak: log.currentStreak(today: now),
                                   newAchievements: fresh,
                                   leveledUpTo: level > levelBefore ? level : nil)
        lastResult = result
        save()
        return result
    }

    /// Achievements that depend on other things (combos, own exercises) — check any time.
    func refresh(content: ContentStore) -> [Achievement] {
        let fresh = unlockNew(content: content, now: Date())
        if !fresh.isEmpty { save() }
        return fresh
    }

    func context(_ content: ContentStore) -> AchievementContext {
        AchievementContext(log: log, distinctExercises: content.lastDone.count,
                           combos: content.customRoutines.count, customExercises: content.customExercises.count)
    }

    func clearLastResult() { lastResult = nil }

    private func unlockNew(content: ContentStore, now: Date) -> [Achievement] {
        let earned = Achievements.earned(context(content))
        let fresh = earned.filter { unlocked[$0.id] == nil }
        for a in fresh {
            unlocked[a.id] = now
            log.xp += Achievements.xpPerAchievement
        }
        return fresh
    }

    private func save() {
        let stored = Stored(log: log, unlocked: unlocked)
        if let data = try? JSONEncoder().encode(stored) { try? data.write(to: url, options: .atomic) }
    }
}
