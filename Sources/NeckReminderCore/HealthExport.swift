import Foundation

/// A spreadsheet of the health numbers NeckReminder already keeps: daily computer-use
/// time, neck-relax time, and the lifetime relax totals that outlive the 30-day daily log.
public enum HealthExport {
    /// UTF-8 CSV without a byte-order mark. Days are written oldest first.
    /// Minutes use a dot as the decimal separator so the file stays one column per field.
    public static func csv(days: [DayStats], log: ActivityLog, now: Date = Date(),
                           calendar: Calendar = .current, chinese: Bool) -> String {
        let ordered = days.sorted { $0.day < $1.day }
        var lines: [String] = [header(chinese)]
        var usage = 0.0
        var relax = 0.0
        for day in ordered {
            usage += day.activeSeconds
            relax += day.relaxSeconds
            lines.append([
                day.day,
                whole(day.activeSeconds),
                oneDecimal(day.activeSeconds / 60),
                whole(day.longestStretch),
                whole(day.relaxSeconds),
                oneDecimal(day.relaxSeconds / 60),
                String(day.relaxSessions),
                String(day.reminders),
                String(day.breaks),
            ].joined(separator: ","))
        }

        lines.append("")
        lines.append(chinese ? "项目,数值" : "metric,value")
        let rows: [(String, String)] = [
            (chinese ? "天数" : "days", String(ordered.count)),
            (chinese ? "使用分钟合计" : "usage_minutes_total", oneDecimal(usage / 60)),
            (chinese ? "放松分钟合计" : "relax_minutes_total", oneDecimal(relax / 60)),
            (chinese ? "累计放松分钟" : "lifetime_relax_minutes", oneDecimal(log.relaxSeconds / 60)),
            (chinese ? "累计完成放松" : "lifetime_relax_sessions", String(log.completedSessions)),
            (chinese ? "累计经验" : "lifetime_xp", String(log.xp)),
            (chinese ? "当前连续天数" : "current_streak_days", String(log.currentStreak(today: now, calendar: calendar))),
            (chinese ? "最长连续天数" : "longest_streak_days", String(log.longestStreak(calendar: calendar))),
            (chinese ? "导出时间" : "exported_at", timestamp(now, calendar: calendar)),
        ]
        for row in rows {
            lines.append("\(field(row.0)),\(field(row.1))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func header(_ chinese: Bool) -> String {
        let columns = chinese
            ? ["日期", "使用秒", "使用分钟", "最长连续秒", "放松秒", "放松分钟", "完成放松", "提醒次数", "自然休息"]
            : ["date", "usage_seconds", "usage_minutes", "longest_stretch_seconds", "relax_seconds",
               "relax_minutes", "relax_sessions", "reminders", "breaks"]
        return columns.joined(separator: ",")
    }

    private static func whole(_ seconds: TimeInterval) -> String {
        String(Int(max(0, seconds).rounded()))
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), max(0, value))
    }

    private static func timestamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    private static func field(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
