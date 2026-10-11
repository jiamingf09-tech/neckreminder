import Foundation

/// Everything the achievements are computed from. Updated after each completed relax session.
public struct ActivityLog: Codable, Equatable {
    public var completedSessions = 0
    public var relaxSeconds: TimeInterval = 0
    /// Relax sessions started within a few minutes of a reminder.
    public var timelyResponses = 0
    /// Completed sessions per day ("yyyy-MM-dd").
    public var sessionDays: [String: Int] = [:]
    /// Sessions of 30 minutes or more.
    public var longSessions = 0
    /// Sessions finished before 10:00.
    public var morningSessions = 0
    public var xp = 0

    public init() {}

    /// Consecutive days with a session, ending today (or yesterday, if today has none yet).
    public func currentStreak(today: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if (sessionDays[DayKey.string(for: day, calendar: calendar)] ?? 0) == 0 {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var streak = 0
        while (sessionDays[DayKey.string(for: day, calendar: calendar)] ?? 0) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    public func longestStreak(calendar: Calendar = .current) -> Int {
        let days = sessionDays.filter { $0.value > 0 }.keys.compactMap { key -> Date? in
            let p = key.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
        }.sorted()
        var best = 0, run = 0
        var previous: Date?
        for d in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = d
        }
        return best
    }

    public var bestDay: Int { sessionDays.values.max() ?? 0 }
}

public enum AchievementTier: Int, Codable, CaseIterable {
    case bronze, silver, gold, legendary

    public var title: String {
        switch self {
        case .bronze: return tr("铜", "Bronze")
        case .silver: return tr("银", "Silver")
        case .gold: return tr("金", "Gold")
        case .legendary: return tr("传奇", "Legendary")
        }
    }
}

public enum AchievementMetric: String, Codable {
    case sessions, timely, streak, relaxMinutes, longSessions, distinctExercises, combos, customExercises, morning, bestDay
}

public struct Achievement: Identifiable, Equatable {
    public let id: String
    public let symbol: String
    public let title: LText
    public let detail: LText
    public let metric: AchievementMetric
    public let goal: Int
    public let tier: AchievementTier
}

/// Inputs that live outside the log (what's in the library / the user's own content).
public struct AchievementContext: Equatable {
    public var log: ActivityLog
    public var distinctExercises: Int
    public var combos: Int
    public var customExercises: Int

    public init(log: ActivityLog, distinctExercises: Int = 0, combos: Int = 0, customExercises: Int = 0) {
        self.log = log
        self.distinctExercises = distinctExercises
        self.combos = combos
        self.customExercises = customExercises
    }
}

public enum Achievements {
    public static let all: [Achievement] = [
        Achievement(id: "firstStep", symbol: "figure.mind.and.body", title: LText("第一次放松", "First stretch"),
                    detail: LText("完成第一次颈椎放松", "Finish your first relax session"), metric: .sessions, goal: 1, tier: .bronze),
        Achievement(id: "tenSessions", symbol: "10.circle.fill", title: LText("坚持十次", "Ten sessions"),
                    detail: LText("累计完成 10 次放松", "Finish 10 relax sessions"), metric: .sessions, goal: 10, tier: .silver),
        Achievement(id: "fiftySessions", symbol: "shield.lefthalf.filled", title: LText("颈椎守护者", "Neck guardian"),
                    detail: LText("累计完成 50 次放松", "Finish 50 relax sessions"), metric: .sessions, goal: 50, tier: .gold),
        Achievement(id: "twoHundred", symbol: "crown.fill", title: LText("传奇伸展者", "Stretch legend"),
                    detail: LText("累计完成 200 次放松", "Finish 200 relax sessions"), metric: .sessions, goal: 200, tier: .legendary),
        Achievement(id: "timely1", symbol: "bolt.fill", title: LText("说到做到", "On it"),
                    detail: LText("提醒后 5 分钟内开始放松", "Start a session within 5 minutes of a reminder"), metric: .timely, goal: 1, tier: .bronze),
        Achievement(id: "timely10", symbol: "cloud.sun.rain.fill", title: LText("及时雨", "Right on time"),
                    detail: LText("10 次及时响应提醒", "Respond to 10 reminders right away"), metric: .timely, goal: 10, tier: .silver),
        Achievement(id: "timely50", symbol: "bolt.circle.fill", title: LText("闪电响应", "Lightning reflexes"),
                    detail: LText("50 次及时响应提醒", "Respond to 50 reminders right away"), metric: .timely, goal: 50, tier: .gold),
        Achievement(id: "streak3", symbol: "flame", title: LText("三天打卡", "Three-day streak"),
                    detail: LText("连续 3 天每天至少放松一次", "Relax at least once a day for 3 days in a row"), metric: .streak, goal: 3, tier: .bronze),
        Achievement(id: "streak7", symbol: "flame.fill", title: LText("一周不断", "One-week streak"),
                    detail: LText("连续 7 天每天至少放松一次", "7 days in a row"), metric: .streak, goal: 7, tier: .silver),
        Achievement(id: "streak30", symbol: "calendar", title: LText("月度全勤", "Perfect month"),
                    detail: LText("连续 30 天每天至少放松一次", "30 days in a row"), metric: .streak, goal: 30, tier: .legendary),
        Achievement(id: "minutes60", symbol: "hourglass", title: LText("累计一小时", "One hour in"),
                    detail: LText("累计放松 60 分钟", "Relax for 60 minutes in total"), metric: .relaxMinutes, goal: 60, tier: .silver),
        Achievement(id: "minutes600", symbol: "hourglass.bottomhalf.filled", title: LText("十小时修炼", "Ten-hour practice"),
                    detail: LText("累计放松 10 小时", "Relax for 10 hours in total"), metric: .relaxMinutes, goal: 600, tier: .gold),
        Achievement(id: "longSession", symbol: "trophy.fill", title: LText("完整恢复", "Full recovery"),
                    detail: LText("完成一次 30 分钟以上的放松", "Finish a session of 30 minutes or more"), metric: .longSessions, goal: 1, tier: .silver),
        Achievement(id: "explorer20", symbol: "map.fill", title: LText("动作探索者", "Explorer"),
                    detail: LText("做过 20 种不同的动作", "Try 20 different exercises"), metric: .distinctExercises, goal: 20, tier: .silver),
        Achievement(id: "explorer45", symbol: "star.circle.fill", title: LText("全能选手", "All-rounder"),
                    detail: LText("做过 45 种不同的动作", "Try 45 different exercises"), metric: .distinctExercises, goal: 45, tier: .gold),
        Achievement(id: "creator", symbol: "square.stack.3d.up.fill", title: LText("编排师", "Choreographer"),
                    detail: LText("创建一个自己的组合", "Create your own combo"), metric: .combos, goal: 1, tier: .bronze),
        Achievement(id: "inventor", symbol: "lightbulb.fill", title: LText("发明家", "Inventor"),
                    detail: LText("新建一个自己的动作", "Create your own exercise"), metric: .customExercises, goal: 1, tier: .bronze),
        Achievement(id: "earlyBird", symbol: "sunrise.fill", title: LText("早起护颈", "Early bird"),
                    detail: LText("上午 10 点前完成一次放松", "Finish a session before 10 am"), metric: .morning, goal: 1, tier: .bronze),
        Achievement(id: "triple", symbol: "3.circle.fill", title: LText("一天三练", "Three a day"),
                    detail: LText("一天之内完成 3 次放松", "Finish 3 sessions in one day"), metric: .bestDay, goal: 3, tier: .silver),
        Achievement(id: "daily5", symbol: "medal.fill", title: LText("自律达人", "Discipline master"),
                    detail: LText("一天之内完成 5 次放松", "Finish 5 sessions in one day"), metric: .bestDay, goal: 5, tier: .gold),
    ]

    public static func value(_ metric: AchievementMetric, _ c: AchievementContext) -> Int {
        switch metric {
        case .sessions: return c.log.completedSessions
        case .timely: return c.log.timelyResponses
        case .streak: return c.log.longestStreak()
        case .relaxMinutes: return Int(c.log.relaxSeconds / 60)
        case .longSessions: return c.log.longSessions
        case .distinctExercises: return c.distinctExercises
        case .combos: return c.combos
        case .customExercises: return c.customExercises
        case .morning: return c.log.morningSessions
        case .bestDay: return c.log.bestDay
        }
    }

    public static func progress(_ a: Achievement, _ c: AchievementContext) -> Double {
        min(1, Double(value(a.metric, c)) / Double(max(1, a.goal)))
    }

    public static func earned(_ c: AchievementContext) -> [Achievement] {
        all.filter { value($0.metric, c) >= $0.goal }
    }

    // MARK: XP & levels

    /// XP for finishing a session: 10 + one per minute, +5 when it answered a reminder promptly.
    public static func xp(activeSeconds: TimeInterval, timely: Bool) -> Int {
        10 + Int(activeSeconds / 60) + (timely ? 5 : 0)
    }

    public static let xpPerAchievement = 20

    /// XP needed to reach `level` (level 1 = 0).
    public static func threshold(_ level: Int) -> Int { 25 * (level - 1) * level }

    public static func level(forXP xp: Int) -> Int {
        var l = 1
        while threshold(l + 1) <= xp { l += 1 }
        return l
    }

    public static func levelTitle(_ level: Int) -> LText {
        switch level {
        case ...1: return LText("颈椎新手", "Neck newbie")
        case 2: return LText("伸展学徒", "Stretch apprentice")
        case 3: return LText("坐姿觉醒者", "Posture aware")
        case 4: return LText("肩颈守护者", "Neck guardian")
        case 5: return LText("放松达人", "Relax pro")
        case 6...7: return LText("体态大师", "Posture master")
        default: return LText("颈椎传奇", "Neck legend")
        }
    }
}
