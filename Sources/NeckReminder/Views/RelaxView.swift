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
    @EnvironmentObject var content: ContentStore
    @State private var minutes: Int?
    @State private var seed = UInt64.random(in: 1...(UInt64.max / 2))
    @State private var editingCombo: CustomRoutine?
    @State private var comboToDelete: CustomRoutine?

    private var length: Int { minutes ?? prefs.defaultRoutineMinutes }

    private var selected: Routine {
        prefs.variedRoutines
            ? RoutineGenerator.generate(minutes: length, lastDone: content.lastDone, seed: seed)
            : ExerciseLibrary.routine(minutes: length)
    }

    var body: some View {
        let routine = selected
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: tr("颈椎舒缓指南", "Neck relief guide"),
                           subtitle: tr("你现在有多少时间？选一个时长，跟着计时一步步做。",
                                        "How much time do you have? Pick a length and follow the timer."))

                HStack(spacing: 10) {
                    ForEach(RoutineGenerator.lengths, id: \.self) { m in
                        durationButton(m)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.title.text).scaledFont(18, weight: .bold)
                                Text(routine.subtitle.text).foregroundColor(.secondary)
                                Text(durationSummary(routine)).scaledFont(11.5).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                session.start(routine)
                            } label: {
                                Label(tr("开始", "Start"), systemImage: "play.fill")
                                    .scaledFont(15, weight: .semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.accent)
                            .controlSize(.large)
                        }
                        HStack {
                            Picker("", selection: $prefs.variedRoutines) {
                                Text(tr("推荐组合（每次不同）", "Varied mix")).tag(true)
                                Text(tr("经典版", "Classic")).tag(false)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 320)
                            if prefs.variedRoutines {
                                Button {
                                    seed = UInt64.random(in: 1...(UInt64.max / 2))
                                } label: {
                                    Label(tr("换一组", "Shuffle"), systemImage: "shuffle")
                                }
                            }
                            Spacer()
                        }
                        Divider()
                        RoutineStepList(routine: routine)
                    }
                }

                combosCard

                GuideExtrasView()
            }
            .padding(24)
        }
        .sheet(item: $editingCombo) { combo in
            ComboEditor(combo: combo)
        }
        .confirmationDialog(tr("删除这个组合？", "Delete this combo?"), isPresented: Binding(
            get: { comboToDelete != nil }, set: { if !$0 { comboToDelete = nil } })) {
            Button(tr("删除", "Delete"), role: .destructive) {
                if let c = comboToDelete { content.delete(c) }
                comboToDelete = nil
            }
        }
    }

    private func durationSummary(_ r: Routine) -> String {
        let prep = prefs.prepSeconds
        let total = r.totalSeconds(withPreparation: prep)
        return tr("\(r.steps.count) 个动作 · 动作 \(formatClock(TimeInterval(r.totalSeconds))) + 每个动作前 \(prep) 秒准备 ≈ \(formatClock(TimeInterval(total)))",
                  "\(r.steps.count) steps · \(formatClock(TimeInterval(r.totalSeconds))) of exercise + \(prep) s to get ready before each ≈ \(formatClock(TimeInterval(total)))")
    }

    private var combosCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("我的组合", "My combos"), systemImage: "square.stack.3d.up").scaledFont(13, weight: .semibold)
                    Spacer()
                    Button {
                        editingCombo = CustomRoutine(name: tr("我的组合 \(content.customRoutines.count + 1)",
                                                             "My combo \(content.customRoutines.count + 1)"))
                    } label: {
                        Label(tr("新建组合", "New combo"), systemImage: "plus")
                    }
                }
                if content.customRoutines.isEmpty {
                    Text(tr("把动作库里喜欢的动作组合起来，按自己的节奏练。也可以在「动作库」里点「加入组合」。",
                            "Combine your favourite exercises and practise at your own pace — or use “Add to combo” in the exercise library."))
                        .scaledFont(12)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(content.customRoutines) { combo in
                    let r = content.routine(for: combo)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(combo.name.isEmpty ? tr("未命名组合", "Untitled combo") : combo.name)
                                .scaledFont(13, weight: .medium)
                            Text(tr("\(r.steps.count) 个动作 · \(formatClock(TimeInterval(r.totalSeconds)))",
                                    "\(r.steps.count) steps · \(formatClock(TimeInterval(r.totalSeconds)))"))
                                .scaledFont(11)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { session.start(r) } label: { Label(tr("开始", "Start"), systemImage: "play.fill") }
                            .disabled(r.steps.isEmpty)
                        Button { editingCombo = combo } label: { Image(systemName: "pencil") }
                            .help(tr("编辑", "Edit"))
                        Button { comboToDelete = combo } label: { Image(systemName: "trash") }
                            .help(tr("删除", "Delete"))
                    }
                    .buttonStyle(.borderless)
                    if combo.id != content.customRoutines.last?.id { Divider() }
                }
            }
        }
    }

    private func durationButton(_ m: Int) -> some View {
        let isSelected = m == length
        return Button {
            minutes = m
        } label: {
            VStack(spacing: 2) {
                Text("\(m)")
                    .scaledFont(26, weight: .bold, design: .rounded)
                Text(tr("分钟", "min")).scaledFont(10.5)
                Text(ExerciseLibrary.routine(minutes: m).title.text).scaledFont(10).lineLimit(1)
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

/// The steps of a routine with durations.
struct RoutineStepList: View {
    let routine: Routine

    var body: some View {
        ForEach(routine.steps) { step in
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
                if step.exercise.isCustom {
                    Text(tr("我的", "mine"))
                        .scaledFont(10)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.accent.opacity(0.15)))
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
                Text(routine.minutes > 0 ? "\(routine.title.text) · \(routine.minutes) \(tr("分钟", "min"))" : routine.title.text)
                    .scaledFont(13, weight: .semibold)
                Spacer()
                voiceButton
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

    /// Voice guidance on / off (off by default).
    private var voiceButton: some View {
        Button {
            prefs.voiceGuidance.toggle()
            session.voiceSettingChanged()
        } label: {
            Label(prefs.voiceGuidance ? tr("语音播报：开", "Voice: on") : tr("语音播报：关", "Voice: off"),
                  systemImage: prefs.voiceGuidance ? "speaker.wave.2.fill" : "speaker.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(prefs.voiceGuidance ? Palette.accent : .secondary)
        }
        .buttonStyle(.borderless)
        .help(tr("切换动作时是否朗读动作名称和要领", "Read out each exercise and its first instruction"))
        .padding(.trailing, 10)
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

    private static let prepGradient = LinearGradient(colors: [Color.orange, Color(red: 0.98, green: 0.75, blue: 0.2)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)

    private func stepView(_ step: RoutineStep) -> some View {
        let preparing = session.phase == .prepare
        return HStack(alignment: .top, spacing: 28) {
            ZStack {
                ProgressRing(progress: 1 - session.stepRemaining / session.phaseLength, lineWidth: 12,
                             gradient: preparing ? Self.prepGradient : Palette.gradient)
                VStack(spacing: 4) {
                    if preparing {
                        Text(tr("准备", "Get ready"))
                            .scaledFont(14, weight: .semibold)
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: step.exercise.symbol)
                            .scaledFont(30)
                            .foregroundColor(Palette.accent)
                    }
                    Text(preparing ? "\(Int(session.stepRemaining.rounded(.up)))" : formatClock(session.stepRemaining))
                        .scaledFont(preparing ? 48 : 40, weight: .bold, design: .rounded)
                        .monospacedDigit()
                    if preparing {
                        Text(tr("然后做 \(formatClock(TimeInterval(step.seconds)))", "then \(formatClock(TimeInterval(step.seconds)))"))
                            .scaledFont(11)
                            .foregroundColor(.secondary)
                    }
                    if session.isPaused {
                        Text(tr("已暂停", "Paused")).scaledFont(10.5).foregroundColor(.orange)
                    }
                }
            }
            .frame(width: 190, height: 190)

            VStack(alignment: .leading, spacing: 12) {
                if preparing {
                    Label(tr("下一个动作 · 先看看怎么做", "Up next · have a look first"), systemImage: "eye")
                        .scaledFont(13, weight: .semibold)
                        .foregroundColor(.orange)
                }
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
            Button { session.next() } label: {
                session.phase == .prepare
                    ? Label(tr("现在开始", "Start now"), systemImage: "forward.end.fill")
                    : Label(tr("下一个", "Next"), systemImage: "forward.fill")
            }
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
                Text(tr("完成了「\(routine.title.text)」（\(routine.steps.count) 个动作，\(formatClock(TimeInterval(routine.totalSeconds)))），计时已重新开始。",
                        "You finished “\(routine.title.text)” (\(routine.steps.count) steps, \(formatClock(TimeInterval(routine.totalSeconds)))). The timer has restarted."))
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
