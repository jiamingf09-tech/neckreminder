import SwiftUI
import NeckReminderCore

struct OverviewView: View {
    @ObservedObject var navigation: Navigation
    @EnvironmentObject var controller: ReminderController
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var notifications: NotificationManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: tr("概览", "Overview"),
                           subtitle: tr("只根据键盘鼠标活跃度与锁屏状态判断，不使用摄像头和麦克风。",
                                        "Based only on input activity and screen state — never the camera or microphone."))
                permissionWarning
                statusCard
                todayTiles
                weekChart
            }
            .padding(24)
        }
        .onAppear { notifications.refreshStatus() }
    }

    // MARK: Status

    private var statusCard: some View {
        Card {
            HStack(spacing: 28) {
                ZStack {
                    ProgressRing(progress: controller.continuousUse / Double(max(1, prefs.intervalMinutes) * 60))
                    VStack(spacing: 2) {
                        Text(formatMinutes(controller.continuousUse))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(tr("连续使用", "continuous use"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 160, height: 160)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Circle().fill(Palette.color(for: controller.state)).frame(width: 10, height: 10)
                        Text(controller.stateTitle).font(.headline)
                    }
                    if let text = controller.suppressionText {
                        HStack {
                            Label(text, systemImage: "moon.zzz").foregroundColor(.secondary)
                            if prefs.enabled {
                                Button(tr("恢复", "Resume")) { controller.resume() }
                            } else {
                                Button(tr("开启提醒", "Turn on")) { prefs.enabled = true }
                            }
                        }
                    } else {
                        Text(controller.isRelaxing
                             ? tr("放松中，计时已暂停", "Relaxing — timer paused")
                             : tr("\(formatMinutes(controller.remaining))后提醒你放松颈椎",
                                  "Next reminder in \(formatMinutes(controller.remaining))"))
                            .font(.title3)
                    }
                    Text(stateExplanation)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            navigation.section = .relax
                        } label: {
                            Label(tr("立即放松", "Relax now"), systemImage: "figure.mind.and.body")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)

                        Button(tr("我刚休息过", "I just took a break")) { controller.startBreak() }
                        Button(tr("预览提醒", "Preview reminder")) { controller.fire(preview: true) }
                    }
                    .controlSize(.large)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var stateExplanation: String {
        let breakMinutes = prefs.breakResetMinutes
        switch controller.state {
        case .active:
            return tr("检测到键盘或鼠标操作。离开电脑 \(breakMinutes) 分钟以上会自动算作休息并重新计时。",
                      "Keyboard or mouse activity detected. Being away for \(breakMinutes)+ minutes counts as a break and restarts the timer.")
        case .passive:
            return tr("暂时没有操作，可能在阅读或观看。这段时间先暂记，等你再次操作时确认；若一直没有操作则视为离开。",
                      "No input for a moment — probably reading or watching. This time is held tentatively and confirmed when you touch the keyboard or mouse again.")
        case .away:
            return tr("你似乎离开了电脑，计时已暂停。离开满 \(breakMinutes) 分钟即算一次休息。",
                      "You seem to be away; the timer is paused. \(breakMinutes) minutes away counts as a break.")
        }
    }

    @ViewBuilder
    private var permissionWarning: some View {
        if prefs.useNotification {
            switch notifications.status {
            case .denied, .alertsOff:
                WarningBox(text: prefs.overlayMode == .off
                           ? tr("系统通知未开启。提醒会改用全屏半透明提示显示。", "Notifications are off, so reminders will use the on-screen overlay instead.")
                           : tr("系统通知未开启，目前只会显示全屏提醒。", "Notifications are off; only the on-screen overlay will be shown.")) {
                    Button(tr("打开系统设置", "Open System Settings")) { notifications.openSystemSettings() }
                }
            case .notDetermined:
                WarningBox(text: tr("NeckReminder 需要通知权限来发送提醒。", "NeckReminder needs permission to send notifications.")) {
                    Button(tr("允许通知", "Allow notifications")) { notifications.requestAuthorization() }
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: Stats

    private var todayTiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("今天", "Today")).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                StatTile(symbol: "desktopcomputer", title: tr("使用时长", "Screen time"), value: formatMinutes(stats.today.activeSeconds))
                StatTile(symbol: "timer", title: tr("最长连续", "Longest stretch"), value: formatMinutes(stats.today.longestStretch))
                StatTile(symbol: "bell", title: tr("提醒次数", "Reminders"), value: "\(stats.today.reminders)")
                StatTile(symbol: "figure.mind.and.body", title: tr("完成放松", "Relax sessions"), value: "\(stats.today.relaxSessions)")
                StatTile(symbol: "cup.and.saucer", title: tr("自然休息", "Breaks"), value: "\(stats.today.breaks)")
            }
        }
    }

    private var weekChart: some View {
        let days = stats.lastDays(7)
        let maxSeconds = max(3600, days.map(\.activeSeconds).max() ?? 0)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("最近 7 天使用时长", "Screen time, last 7 days")).font(.headline)
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(days) { day in
                        VStack(spacing: 6) {
                            Text(day.activeSeconds >= 60 ? shortHours(day.activeSeconds) : "")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(day.day == stats.today.day ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Palette.accent.opacity(0.35)))
                                .frame(height: max(4, 110 * day.activeSeconds / maxSeconds))
                            Text(weekdayLabel(day.day))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 150, alignment: .bottom)
            }
        }
    }

    private func shortHours(_ seconds: TimeInterval) -> String {
        let h = seconds / 3600
        return h >= 1 ? String(format: "%.1fh", h) : "\(Int(seconds / 60))m"
    }

    private func weekdayLabel(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return "" }
        let weekday = Calendar.current.component(.weekday, from: date)
        return WeekdayNames.short(weekday)
    }
}

enum WeekdayNames {
    /// Calendar weekday (1 = Sunday) → short label in the app language.
    static func short(_ weekday: Int) -> String {
        let zh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let i = max(1, min(7, weekday)) - 1
        return tr(zh[i], en[i])
    }

    /// Monday-first order.
    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]
}
