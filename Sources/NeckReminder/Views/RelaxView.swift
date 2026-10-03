import SwiftUI
import NeckReminderCore

struct RelaxView: View {
    @EnvironmentObject var session: RelaxSession

    var body: some View {
        if session.routine != nil {
            RoutinePlayerView()
        } else {
            RoutinePickerView()
        }
    }
}

// MARK: - Picking a routine

struct RoutinePickerView: View {
    @EnvironmentObject var session: RelaxSession
    @EnvironmentObject var prefs: Preferences
    @State private var minutes: Int?

    private var selected: Routine { ExerciseLibrary.routine(minutes: minutes ?? prefs.defaultRoutineMinutes) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: tr("颈椎舒缓指南", "Neck relief guide"),
                           subtitle: tr("你现在有多少时间？选一个时长，跟着计时一步步做。",
                                        "How much time do you have? Pick a length and follow the timer."))

                HStack(spacing: 10) {
                    ForEach(ExerciseLibrary.routines) { routine in
                        durationButton(routine)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selected.title.text).scaledFont(18, weight: .bold)
                                Text(selected.subtitle.text).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                session.start(selected)
                            } label: {
                                Label(tr("开始 \(selected.minutes) 分钟放松", "Start \(selected.minutes)-minute session"),
                                      systemImage: "play.fill")
                                    .scaledFont(15, weight: .semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.accent)
                            .controlSize(.large)
                        }
                        Divider()
                        ForEach(selected.steps) { step in
                            HStack(spacing: 10) {
                                Image(systemName: step.exercise.symbol)
                                    .frame(width: 22)
                                    .foregroundColor(Palette.accent)
                                Text(step.title)
                                if step.exercise.needsStanding {
                                    Text(tr("站立", "standing"))
                                        .scaledFont(10)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                                }
                                Spacer()
                                Text(formatClock(TimeInterval(step.seconds)))
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            .scaledFont(12)
                        }
                    }
                }

                GuideExtrasView()
            }
            .padding(24)
        }
    }

    private func durationButton(_ routine: Routine) -> some View {
        let isSelected = routine.minutes == selected.minutes
        return Button {
            minutes = routine.minutes
        } label: {
            VStack(spacing: 2) {
                Text("\(routine.minutes)")
                    .scaledFont(26, weight: .bold, design: .rounded)
                Text(tr("分钟", "min")).scaledFont(10.5)
                Text(routine.title.text).scaledFont(10).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(isSelected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Ergonomics, video references and the safety note.
struct GuideExtrasView: View {
    @State private var video: VideoLink?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("工位小调整，效果常常比拉伸更持久", "Small desk changes often help more than any stretch"),
                          systemImage: "desktopcomputer")
                        .scaledFont(13, weight: .semibold)
                    ForEach(ExerciseLibrary.ergonomicTips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text(tip.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("参考视频（YouTube）", "Video references (YouTube)"), systemImage: "play.rectangle")
                        .scaledFont(13, weight: .semibold)
                    Text(tr("本指南的动作参考了 YouTube 上常见的 “neck pain relief exercises” 系列，点击可搜索对应频道的示范视频。",
                            "These routines follow the popular “neck pain relief exercises” videos on YouTube. Click to search for demonstrations."))
                        .scaledFont(12)
                        .foregroundColor(.secondary)
                    ForEach(ExerciseLibrary.videoReferences, id: \.query) { ref in
                        Button {
                            video = .youtube(ref.title.text, query: ref.query)
                        } label: {
                            Label(ref.title.text, systemImage: "play.rectangle")
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "cross.case").foregroundColor(.red)
                Text(ExerciseLibrary.safetyNote.text)
                    .scaledFont(12)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $video) { VideoSheet(video: $0) }
    }
}

// MARK: - Running a routine

struct RoutinePlayerView: View {
    @EnvironmentObject var session: RelaxSession
    @EnvironmentObject var prefs: Preferences
    @State private var video: VideoLink?

    var body: some View {
        if session.finished {
            finishedView
        } else if let step = session.currentStep, let routine = session.routine {
            VStack(spacing: 0) {
                header(routine)
                ScrollView {
                    stepView(step)
                        .padding(24)
                }
                controls
            }
            .sheet(item: $video) { VideoSheet(video: $0) }
        }
    }

    private func header(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(routine.title.text) · \(routine.minutes) \(tr("分钟", "min"))").scaledFont(13, weight: .semibold)
                Spacer()
                textSizeButtons
                Text(tr("剩余 \(formatClock(session.totalRemaining))", "\(formatClock(session.totalRemaining)) left"))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            ProgressView(value: session.overallProgress)
                .tint(Palette.accent)
            Text(tr("第 \(session.index + 1) / \(routine.steps.count) 个动作", "Step \(session.index + 1) of \(routine.steps.count)"))
                .scaledFont(10.5)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    /// Quick text size adjustment right where the guidance is read.
    private var textSizeButtons: some View {
        HStack(spacing: 2) {
            Button { prefs.textScale = TextScale.step(prefs.textScale, up: false) } label: {
                Text("A−").font(.system(size: 11, weight: .semibold))
            }
            .disabled(prefs.textScale <= TextScale.options.first! + 0.001)
            .help(tr("缩小文字", "Smaller text"))
            Text(TextScale.label(prefs.textScale))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 40)
            Button { prefs.textScale = TextScale.step(prefs.textScale, up: true) } label: {
                Text("A+").font(.system(size: 14, weight: .semibold))
            }
            .disabled(prefs.textScale >= TextScale.options.last! - 0.001)
            .help(tr("放大文字", "Larger text"))
        }
        .buttonStyle(.borderless)
        .padding(.trailing, 12)
    }

    private func stepView(_ step: RoutineStep) -> some View {
        HStack(alignment: .top, spacing: 28) {
            ZStack {
                ProgressRing(progress: 1 - session.stepRemaining / Double(max(1, step.seconds)), lineWidth: 12)
                VStack(spacing: 4) {
                    Image(systemName: step.exercise.symbol)
                        .scaledFont(30)
                        .foregroundColor(Palette.accent)
                    Text(formatClock(session.stepRemaining))
                        .scaledFont(40, weight: .bold, design: .rounded)
                        .monospacedDigit()
                    if session.isPaused {
                        Text(tr("已暂停", "Paused")).scaledFont(10.5).foregroundColor(.orange)
                    }
                }
            }
            .frame(width: 190, height: 190)

            VStack(alignment: .leading, spacing: 12) {
                Text(step.exercise.name.text)
                    .scaledFont(34, weight: .bold, design: .rounded)
                if let side = step.side {
                    Text(side.label)
                        .scaledFont(16, weight: .semibold)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.accent.opacity(0.18)))
                }
                Text(step.exercise.summary.text)
                    .scaledFont(16)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(step.exercise.howTo.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).").monospacedDigit().foregroundColor(Palette.accent)
                            Text(line.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .scaledFont(19)
                Label(step.exercise.dosage.text, systemImage: "repeat").scaledFont(16, weight: .medium)
                if let caution = step.exercise.caution {
                    Label(caution.text, systemImage: "exclamationmark.triangle")
                        .scaledFont(15)
                        .foregroundColor(.orange)
                }
                Button {
                    video = .youtube(step.exercise.name.text, query: step.exercise.youtubeQuery)
                } label: {
                    Label(tr("观看示范视频", "Watch a demo video"), systemImage: "play.rectangle")
                        .scaledFont(14)
                }
                .buttonStyle(.link)
                if let next = session.nextStep {
                    Text(tr("下一个：\(next.title)", "Up next: \(next.title)"))
                        .scaledFont(14)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { session.previous() } label: { Label(tr("上一个", "Previous"), systemImage: "backward.fill") }
                .disabled(session.index == 0)
            Button { session.togglePause() } label: {
                Label(session.isPaused ? tr("继续", "Resume") : tr("暂停", "Pause"),
                      systemImage: session.isPaused ? "play.fill" : "pause.fill")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            Button { session.next() } label: { Label(tr("下一个", "Next"), systemImage: "forward.fill") }
            Spacer()
            Button(role: .destructive) { session.stop() } label: { Text(tr("结束", "End")) }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill")
                .scaledFont(64)
                .foregroundStyle(Palette.gradient)
            Text(tr("完成！你的颈椎会感谢你", "Done! Your neck says thanks"))
                .scaledFont(28, weight: .bold, design: .rounded)
            if let routine = session.routine {
                Text(tr("完成了 \(routine.minutes) 分钟的「\(routine.title.text)」，计时已重新开始。",
                        "You finished the \(routine.minutes)-minute “\(routine.title.text)”. The timer has restarted."))
                    .foregroundColor(.secondary)
            }
            HStack {
                if let routine = session.routine {
                    Button(tr("再来一次", "Again")) { session.start(routine) }
                }
                Button(tr("返回", "Back")) { session.close() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
