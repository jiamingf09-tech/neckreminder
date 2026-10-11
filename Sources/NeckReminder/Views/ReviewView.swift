import AppKit
import SwiftUI
import NeckReminderCore

/// "Was that right?" — the day's timeline plus every longer silence, each correctable with
/// one click. Corrections fix the statistics and train the presence model.
struct ReviewView: View {
    @EnvironmentObject var learning: LearningStore
    @EnvironmentObject var controller: ReminderController
    @EnvironmentObject var prefs: Preferences
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: tr("回顾", "Review"),
                           subtitle: tr("看看判断得对不对。点一下就能纠正，纠正得越多，判断越贴合你的习惯。",
                                        "Check what was detected. One click corrects it — the more you correct, the better it fits you."))
                dayPicker
                timelineCard
                gapsCard
                learningCard
            }
            .padding(24)
        }
    }

    // MARK: Day picker

    private var dayPicker: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        return HStack(spacing: 8) {
            ForEach(days, id: \.self) { d in
                Chip(title: cal.isDateInToday(d) ? tr("今天", "Today")
                            : "\(WeekdayNames.short(cal.component(.weekday, from: d))) \(cal.component(.day, from: d))",
                     selected: cal.isDate(d, inSameDayAs: day)) { day = d }
            }
        }
    }

    // MARK: Timeline

    private var timelineCard: some View {
        let segments = learning.timeline.segments(on: day)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("时间线", "Timeline")).scaledFont(13, weight: .semibold)
                if segments.isEmpty {
                    Text(tr("这一天还没有记录。", "Nothing recorded for this day.")).foregroundColor(.secondary)
                } else {
                    TimelineBar(segments: segments)
                    HStack(spacing: 14) {
                        legend(.active, tr("使用电脑", "Using"))
                        legend(.passive, tr("阅读 / 观看", "Reading / watching"))
                        legend(.away, tr("离开", "Away"))
                        legend(.relax, tr("放松跟练", "Relax session"))
                    }
                    .scaledFont(11)
                }
            }
        }
    }

    private func legend(_ kind: SegmentKind, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(TimelineBar.color(kind)).frame(width: 12, height: 8)
            Text(title).foregroundColor(.secondary)
        }
    }

    // MARK: Silences

    private var episodesForDay: [GapEpisode] {
        let cal = Calendar.current
        return learning.episodes
            .filter { cal.isDate($0.gap.end, inSameDayAs: day) && $0.gap.duration >= 120 }
            .sorted {
                if $0.awaitingReview != $1.awaitingReview { return $0.awaitingReview }
                return $0.gap.end > $1.gap.end
            }
    }

    private var gapsCard: some View {
        let list = episodesForDay
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("没有操作的时间段", "Stretches without input")).scaledFont(13, weight: .semibold)
                    Spacer()
                    Text(tr("2 分钟以上", "2 min or longer")).scaledFont(11).foregroundColor(.secondary)
                }
                if list.isEmpty {
                    Text(tr("这一天没有较长的无操作时间。", "No longer silences on this day.")).foregroundColor(.secondary)
                }
                ForEach(list) { e in
                    GapRow(episode: e) { label in controller.answer(e.id, label) }
                    if e.id != list.last?.id { Divider() }
                }
            }
        }
    }

    // MARK: Learning summary

    private var learningCard: some View {
        let accuracy = PresenceModel.accuracy(learning.episodes)
        let apps = learning.learnedApps()
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(tr("学习情况", "What it has learned"), systemImage: "brain.head.profile").scaledFont(13, weight: .semibold)
                if accuracy.total > 0 {
                    Text(tr("你回答过 \(accuracy.total) 次，回答前的判断有 \(Int(Double(accuracy.correct) / Double(accuracy.total) * 100))% 是对的。",
                            "You answered \(accuracy.total) times; the guess before your answer was right \(Int(Double(accuracy.correct) / Double(accuracy.total) * 100))% of the time."))
                } else {
                    Text(tr("还没有回答。回到电脑时右下角会偶尔问一句，答一下就能让判断更准。",
                            "No answers yet. When you come back, a small question occasionally appears bottom-right — answering it improves detection."))
                        .foregroundColor(.secondary)
                }
                if !apps.isEmpty {
                    Text(tr("各应用中，没有操作多久会被认为离开：", "Per app, stillness before you count as away:"))
                        .scaledFont(12).foregroundColor(.secondary)
                    ForEach(apps.prefix(8), id: \.name) { app in
                        HStack {
                            Text(app.name)
                            Spacer()
                            Text(formatMinutes(app.grace)).monospacedDigit()
                            Text(tr("（\(app.answers) 次回答）", "(\(app.answers) answers)")).foregroundColor(.secondary)
                        }
                        .scaledFont(12)
                    }
                }
                if !prefs.noAskApps.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tr("不再询问：", "Never asked for:")).foregroundColor(.secondary)
                        Text(prefs.noAskApps.map(appName).joined(separator: "、"))
                        Spacer()
                        Button(tr("恢复询问", "Ask again")) { prefs.noAskApps = [] }
                            .buttonStyle(.borderless)
                    }
                    .scaledFont(12)
                }
                HStack {
                    Text(tr("数据只保存在这台 Mac 上：时间、应用名称和是否在播放 / 通话等状态，不含任何按键或屏幕内容。",
                            "Stored only on this Mac: times, app names and states like playing / in a call — never keystrokes or screen content."))
                        .scaledFont(11)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(tr("清空学习数据…", "Clear learning data…")) { confirmClear = true }
                }
            }
        }
        .confirmationDialog(tr("清空所有学习数据和时间线？", "Clear all learning data and the timeline?"),
                            isPresented: $confirmClear) {
            Button(tr("清空", "Clear"), role: .destructive) { learning.clearAll() }
        } message: {
            Text(tr("判断会回到设置里的默认规则。", "Detection goes back to the default rules from Settings."))
        }
    }

    private func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}

private struct GapRow: View {
    let episode: GapEpisode
    let answer: (PresenceLabel) -> Void

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if episode.awaitingReview && episode.source != .user {
                Circle().fill(Color.orange).frame(width: 8, height: 8).help(tr("当时在演示或全屏，没有询问", "Not asked at the time (presenting / full screen)"))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(Self.time.string(from: episode.gap.start)) – \(Self.time.string(from: episode.gap.end))")
                        .monospacedDigit()
                    Text(formatMinutes(episode.gap.duration)).foregroundColor(.secondary)
                }
                .scaledFont(13, weight: .medium)
                if let detail = episode.context.summary {
                    Text(detail)
                        .scaledFont(12)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    ForEach(contextTags, id: \.self) { tag in
                        Text(tag)
                            .scaledFont(10)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    Text(statusText).scaledFont(11).foregroundColor(.secondary)
                }
            }
            .layoutPriority(1)
            Spacer()
            choice(.present, tr("使用电脑", "Using"))
            choice(.away, tr("离开了", "Away"))
        }
    }

    private var contextTags: [String] {
        var tags: [String] = []
        let c = episode.context
        if c.videoPlaying { tags.append(tr("视频", "Video")) }
        if c.pictureInPicture { tags.append(tr("画中画", "PiP")) }
        if c.audioOnly { tags.append(tr("音乐 / 音频", "Audio")) }
        switch c.call {
        case .video: tags.append(tr("视频通话", "Video call"))
        case .meeting: tags.append(tr("会议", "Meeting"))
        case .voice: tags.append(tr("语音通话", "Voice call"))
        case .none: break
        }
        if c.frontmostFullscreen { tags.append(tr("全屏", "Full screen")) }
        if episode.gap.hadHardAway { tags.append(tr("锁屏 / 睡眠", "Locked / asleep")) }
        return tags
    }

    private var statusText: String {
        let present = episode.effectivePresent
        let what = present ? tr("使用电脑", "using") : tr("离开", "away")
        switch episode.source {
        case .user?: return tr("你的回答：\(what)", "Your answer: \(what)")
        case .probe?: return tr("轻提示确认：\(what)", "Confirmed by hint: \(what)")
        case .implicit?: return tr("自动推断：\(what)", "Inferred: \(what)")
        case nil: return tr("自动判断：\(what)", "Detected: \(what)")
        }
    }

    private func choice(_ label: PresenceLabel, _ title: String) -> some View {
        let selected = episode.effectivePresent == (label == .present)
        let confirmed = selected && episode.source == .user
        return Button { answer(label) } label: {
            Text(title)
                .scaledFont(12, weight: confirmed ? .semibold : .regular)
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 4)
                .foregroundColor(confirmed ? .white : .primary)
                .background(
                    Capsule().fill(confirmed ? AnyShapeStyle(Palette.gradient)
                                   : AnyShapeStyle(Color.primary.opacity(selected ? 0.14 : 0.05)))
                )
        }
        .buttonStyle(.plain)
    }
}

/// The day as a colored bar with hour marks.
struct TimelineBar: View {
    let segments: [TimelineSegment]

    /// Four clearly different hues (green / amber / grey / violet) so the bar reads at a glance.
    static func color(_ kind: SegmentKind) -> Color {
        switch kind {
        case .active: return Color(red: 0.16, green: 0.68, blue: 0.38)   // green: using
        case .passive: return Color(red: 0.98, green: 0.66, blue: 0.14)  // amber: reading / watching
        case .away: return Color.gray.opacity(0.30)                     // grey: away
        case .relax: return Color(red: 0.55, green: 0.36, blue: 0.96)   // violet: relax session
        }
    }

    private var range: (start: Date, end: Date) {
        let first = segments.first?.start ?? Date()
        let last = segments.last?.end ?? Date()
        let start = Self.floorHour(first)
        var end = Self.floorHour(last.addingTimeInterval(3599))
        if end.timeIntervalSince(start) < 3600 { end = start.addingTimeInterval(3600) }
        return (start, end)
    }

    private static func floorHour(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: d)) ?? d
    }

    var body: some View {
        let r = range
        let span = r.end.timeIntervalSince(r.start)
        let hours = Int((span / 3600).rounded())
        let step = hours > 12 ? 3 : (hours > 6 ? 2 : 1)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                        let x = geo.size.width * CGFloat(s.start.timeIntervalSince(r.start) / span)
                        let w = max(1, geo.size.width * CGFloat(s.duration / span))
                        Rectangle()
                            .fill(Self.color(s.kind))
                            .frame(width: w, height: geo.size.height)
                            .offset(x: x)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 30)
            GeometryReader { geo in
                ForEach(Array(stride(from: 0, through: hours, by: step)), id: \.self) { h in
                    let x = geo.size.width * CGFloat(Double(h) * 3600 / span)
                    Text(Self.hourLabel(r.start.addingTimeInterval(Double(h) * 3600)))
                        .scaledFont(10)
                        .foregroundColor(.secondary)
                        .fixedSize()
                        .position(x: min(max(x, 14), geo.size.width - 14), y: 7)
                }
            }
            .frame(height: 14)
        }
    }

    private static func hourLabel(_ d: Date) -> String {
        String(format: "%02d:00", Calendar.current.component(.hour, from: d))
    }
}
