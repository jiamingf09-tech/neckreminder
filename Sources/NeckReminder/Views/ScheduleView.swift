import SwiftUI
import NeckReminderCore

struct ScheduleView: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var controller: ReminderController

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    ForEach(WeekdayNames.mondayFirst, id: \.self) { weekday in
                        let skipped = prefs.schedule.skippedWeekdays.contains(weekday)
                        Chip(title: WeekdayNames.short(weekday), selected: !skipped) {
                            if skipped {
                                prefs.schedule.skippedWeekdays.remove(weekday)
                            } else {
                                prefs.schedule.skippedWeekdays.insert(weekday)
                            }
                        }
                    }
                }
                HStack {
                    Button(tr("仅工作日", "Weekdays only")) { prefs.schedule.skippedWeekdays = [1, 7] }
                    Button(tr("每天", "Every day")) { prefs.schedule.skippedWeekdays = [] }
                }
            } header: {
                Text(tr("提醒的日子", "Reminder days"))
            } footer: {
                Text(tr("高亮的日子会提醒；点击可切换为跳过。", "Highlighted days get reminders; click to skip a day."))
            }

            Section {
                if prefs.schedule.quietPeriods.isEmpty {
                    Text(tr("还没有免打扰时段。", "No quiet hours yet.")).foregroundColor(.secondary)
                }
                ForEach(prefs.schedule.quietPeriods) { range in
                    HStack(spacing: 12) {
                        Toggle("", isOn: enabledBinding(range.id)).labelsHidden()
                        DatePicker("", selection: timeBinding(range.id, start: true), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("–")
                        DatePicker("", selection: timeBinding(range.id, start: false), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        if range.endMinute < range.startMinute {
                            Text(tr("（跨夜）", "(overnight)")).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            prefs.schedule.quietPeriods.removeAll { $0.id == range.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button {
                        prefs.schedule.quietPeriods.append(TimeRange(startMinute: 18 * 60, endMinute: 19 * 60))
                    } label: { Label(tr("添加时段", "Add period"), systemImage: "plus") }
                    Button(tr("午休 12:00–13:30", "Lunch 12:00–13:30")) {
                        prefs.schedule.quietPeriods.append(TimeRange(startMinute: 12 * 60, endMinute: 13 * 60 + 30))
                    }
                    Button(tr("夜间 22:00–08:00", "Night 22:00–08:00")) {
                        prefs.schedule.quietPeriods.append(TimeRange(startMinute: 22 * 60, endMinute: 8 * 60))
                    }
                }
            } header: {
                Text(tr("免打扰时段", "Quiet hours"))
            } footer: {
                Text(tr("这些时间段内不会弹出提醒（使用时长仍会统计）。结束时间早于开始时间表示跨夜。",
                        "No reminders during these times (usage is still tracked). An end before the start means overnight."))
            }

            Section {
                if let text = controller.suppressionText {
                    HStack {
                        Label(text, systemImage: "moon.zzz")
                        Spacer()
                        Button(tr("恢复提醒", "Resume")) { controller.resume() }
                    }
                } else {
                    Text(tr("提醒正常运行中。", "Reminders are running.")).foregroundColor(.secondary)
                }
                HStack {
                    Button(tr("暂停 1 小时", "Pause 1 hour")) { controller.pause(for: 3600) }
                    Button(tr("暂停 2 小时", "Pause 2 hours")) { controller.pause(for: 7200) }
                    Button(tr("暂停到明天", "Until tomorrow")) { controller.pauseUntilTomorrow() }
                    Button(tr("今日忽略", "Skip today")) { controller.handle(.skipToday) }
                }
            } header: {
                Text(tr("临时暂停", "Pause"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("时间安排", "Schedule"))
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { prefs.schedule.quietPeriods.first { $0.id == id }?.enabled ?? false },
            set: { value in
                if let i = prefs.schedule.quietPeriods.firstIndex(where: { $0.id == id }) {
                    prefs.schedule.quietPeriods[i].enabled = value
                }
            })
    }

    private func timeBinding(_ id: UUID, start: Bool) -> Binding<Date> {
        Binding(
            get: {
                let range = prefs.schedule.quietPeriods.first { $0.id == id }
                let minute = (start ? range?.startMinute : range?.endMinute) ?? 0
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                guard let i = prefs.schedule.quietPeriods.firstIndex(where: { $0.id == id }) else { return }
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                if start {
                    prefs.schedule.quietPeriods[i].startMinute = minute
                } else {
                    prefs.schedule.quietPeriods[i].endMinute = minute
                }
            })
    }
}
