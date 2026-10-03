import Foundation

/// Decides *when* (in continuous-use time) the next reminder is due.
/// All values are measured in seconds of continuous use as reported by `UsageTracker`,
/// so time spent away from the computer never brings a reminder closer.
public struct ReminderPolicy: Equatable {
    /// Remind after this much continuous use.
    public var interval: TimeInterval
    /// If a reminder is shown but not acted on, remind again after this much more use.
    public var repeatInterval: TimeInterval
    /// Continuous use at which the next reminder is due.
    public private(set) var nextDue: TimeInterval

    public init(interval: TimeInterval, repeatInterval: TimeInterval) {
        self.interval = max(60, interval)
        self.repeatInterval = max(60, repeatInterval)
        self.nextDue = self.interval
    }

    public func isDue(use: TimeInterval) -> Bool { use >= nextDue }

    public func remaining(use: TimeInterval) -> TimeInterval { max(0, nextDue - use) }

    /// New cycle (a break was taken or the counter was reset).
    public mutating func resetCycle() { nextDue = interval }

    /// A reminder was just shown.
    public mutating func markFired(use: TimeInterval) { nextDue = use + repeatInterval }

    /// "Remind me in N minutes".
    public mutating func snooze(_ seconds: TimeInterval, use: TimeInterval) { nextDue = use + max(60, seconds) }

    /// "Skip this one": the next reminder comes after a full interval.
    public mutating func skipThisTime(use: TimeInterval) { nextDue = use + interval }

    /// Settings changed. Keep the cycle consistent without firing immediately.
    public mutating func updateIntervals(interval newInterval: TimeInterval,
                                         repeatInterval newRepeat: TimeInterval,
                                         use: TimeInterval) {
        let newInterval = max(60, newInterval)
        let wasFreshCycle = nextDue == interval
        interval = newInterval
        repeatInterval = max(60, newRepeat)
        if wasFreshCycle {
            nextDue = max(newInterval, use + 60)
        }
    }
}

/// A daily time window, in minutes since midnight. May wrap past midnight (22:00 → 07:00).
public struct TimeRange: Codable, Hashable, Identifiable {
    public var id: UUID
    public var startMinute: Int
    public var endMinute: Int
    public var enabled: Bool

    public init(id: UUID = UUID(), startMinute: Int, endMinute: Int, enabled: Bool = true) {
        self.id = id
        self.startMinute = ((startMinute % 1440) + 1440) % 1440
        self.endMinute = ((endMinute % 1440) + 1440) % 1440
        self.enabled = enabled
    }

    public func contains(minuteOfDay m: Int) -> Bool {
        if startMinute == endMinute { return false }
        if startMinute < endMinute { return m >= startMinute && m < endMinute }
        return m >= startMinute || m < endMinute
    }

    public static func label(forMinute m: Int) -> String {
        String(format: "%02d:%02d", m / 60, m % 60)
    }

    public var label: String { "\(Self.label(forMinute: startMinute)) – \(Self.label(forMinute: endMinute))" }
}

/// "Don't remind me on these days / at these times."
public struct ScheduleRules: Codable, Equatable {
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday) on which no reminders are shown.
    public var skippedWeekdays: Set<Int>
    public var quietPeriods: [TimeRange]

    public init(skippedWeekdays: Set<Int> = [], quietPeriods: [TimeRange] = []) {
        self.skippedWeekdays = skippedWeekdays
        self.quietPeriods = quietPeriods
    }

    public func isSkippedDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        skippedWeekdays.contains(calendar.component(.weekday, from: date))
    }

    public func activeQuietPeriod(at date: Date, calendar: Calendar = .current) -> TimeRange? {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return quietPeriods.first { $0.enabled && $0.contains(minuteOfDay: minute) }
    }
}

public enum SuppressionReason: Equatable {
    case disabled
    case paused(until: Date)
    case ignoredToday
    case skippedWeekday
    case quietPeriod(TimeRange)
}

public enum ReminderGate {
    /// Why reminders are currently not allowed, or nil when they are.
    public static func suppression(at date: Date,
                                   enabled: Bool,
                                   pausedUntil: Date?,
                                   ignoredDay: String?,
                                   rules: ScheduleRules,
                                   calendar: Calendar = .current) -> SuppressionReason? {
        if !enabled { return .disabled }
        if let until = pausedUntil, until > date { return .paused(until: until) }
        if let day = ignoredDay, day == DayKey.string(for: date, calendar: calendar) { return .ignoredToday }
        if rules.isSkippedDay(date, calendar: calendar) { return .skippedWeekday }
        if let range = rules.activeQuietPeriod(at: date, calendar: calendar) { return .quietPeriod(range) }
        return nil
    }
}

public enum DayKey {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func startOfTomorrow(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }
}

/// Per-day usage statistics.
public struct DayStats: Codable, Equatable, Identifiable {
    public var day: String
    public var activeSeconds: TimeInterval = 0
    public var longestStretch: TimeInterval = 0
    public var reminders: Int = 0
    public var relaxSessions: Int = 0
    public var relaxSeconds: TimeInterval = 0
    public var breaks: Int = 0

    public var id: String { day }

    public init(day: String) { self.day = day }
}
