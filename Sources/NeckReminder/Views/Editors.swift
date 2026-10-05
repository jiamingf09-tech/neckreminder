import SwiftUI
import NeckReminderCore

/// Create or edit an exercise of your own. You can start from any library exercise as a
/// template (its instructions, duration and demo search are copied).
struct ExerciseEditor: View {
    @EnvironmentObject var content: ContentStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomExercise
    @State private var stepsText: String
    @State private var video: VideoLink?

    init(exercise: CustomExercise) {
        _draft = State(initialValue: exercise)
        _stepsText = State(initialValue: exercise.steps.joined(separator: "\n"))
    }

    private var isNew: Bool { !content.customExercises.contains { $0.id == draft.id } }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? tr("新建动作", "New exercise") : tr("编辑动作", "Edit exercise"))
                    .scaledFont(16, weight: .semibold)
                Spacer()
                Menu {
                    ForEach(ExerciseCategory.allCases, id: \.self) { category in
                        Menu(category.title) {
                            ForEach(ExerciseLibrary.all.filter { $0.category == category }) { e in
                                Button(e.name.text) { useTemplate(e) }
                            }
                        }
                    }
                } label: {
                    Label(tr("以库中动作为模板", "Start from a library exercise"), systemImage: "doc.on.doc")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(16)
            Divider()
            Form {
                TextField(tr("名称", "Name"), text: $draft.name)
                TextField(tr("简介（可选）", "Summary (optional)"), text: $draft.summary, axis: .vertical)
                    .lineLimit(2...4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("动作要领（每行一步）", "Instructions (one step per line)"))
                    TextEditor(text: $stepsText)
                        .font(.system(size: 13))
                        .frame(minHeight: 110)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                }
                Stepper(value: $draft.seconds, in: 10...600, step: 5) {
                    Text(draft.bilateral ? tr("时长：每侧 \(draft.seconds) 秒", "Duration: \(draft.seconds) s per side")
                                         : tr("时长：\(draft.seconds) 秒", "Duration: \(draft.seconds) s"))
                }
                Toggle(tr("左右两侧分别做", "Done on each side"), isOn: $draft.bilateral)
                Toggle(tr("需要站立", "Needs standing"), isOn: $draft.standing)
                Picker(tr("分类", "Category"), selection: $draft.category) {
                    ForEach(ExerciseCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                HStack {
                    TextField(tr("示范视频搜索词（默认用名称）", "Demo video search (defaults to the name)"), text: $draft.videoQuery)
                    Button(tr("预览", "Preview")) {
                        let q = draft.videoQuery.isEmpty ? draft.name : draft.videoQuery
                        video = .youtube(draft.name, query: q)
                    }
                    .disabled(draft.name.isEmpty && draft.videoQuery.isEmpty)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if !isNew {
                    Button(tr("删除动作", "Delete"), role: .destructive) {
                        content.delete(draft)
                        dismiss()
                    }
                }
                Spacer()
                Button(tr("取消", "Cancel")) { dismiss() }
                Button(tr("保存", "Save")) {
                    draft.steps = stepsText.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    content.save(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 560, height: 640)
        .sheet(item: $video) { VideoSheet(video: $0) }
    }

    private func useTemplate(_ e: Exercise) {
        draft.name = e.name.text + tr("（我的）", " (mine)")
        draft.summary = e.summary.text
        stepsText = e.howTo.map(\.text).joined(separator: "\n")
        draft.seconds = e.defaultSeconds
        draft.bilateral = e.bilateral
        draft.standing = e.needsStanding
        draft.category = e.category
        draft.videoQuery = e.youtubeQuery
    }
}

/// Build "my combo": pick exercises from the library (and your own), set durations, reorder.
struct ComboEditor: View {
    @EnvironmentObject var content: ContentStore
    @EnvironmentObject var prefs: Preferences
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomRoutine

    init(combo: CustomRoutine) {
        _draft = State(initialValue: combo)
    }

    private var isNew: Bool { !content.customRoutines.contains { $0.id == draft.id } }

    var body: some View {
        let routine = content.routine(for: draft)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? tr("新建组合", "New combo") : tr("编辑组合", "Edit combo"))
                    .scaledFont(16, weight: .semibold)
                Spacer()
                Text(tr("\(routine.steps.count) 个动作 · \(formatClock(TimeInterval(routine.totalSeconds)))（含准备 \(formatClock(TimeInterval(routine.totalSeconds(withPreparation: prefs.prepSeconds)))))",
                        "\(routine.steps.count) steps · \(formatClock(TimeInterval(routine.totalSeconds))) (\(formatClock(TimeInterval(routine.totalSeconds(withPreparation: prefs.prepSeconds)))) with get-ready time)"))
                    .scaledFont(11.5)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            TextField(tr("组合名称", "Combo name"), text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            List {
                ForEach(draft.items) { item in
                    itemRow(item)
                }
                .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }
                if draft.items.isEmpty {
                    Text(tr("还没有动作，点下方「添加动作」。可以拖动排序。", "No exercises yet — use “Add exercise” below. Drag to reorder."))
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Menu {
                    let mine = content.customExercises.map(\.exercise)
                    if !mine.isEmpty {
                        Menu(tr("我的动作", "My exercises")) {
                            ForEach(mine) { e in Button(e.name.text) { append(e) } }
                        }
                    }
                    ForEach(ExerciseCategory.allCases, id: \.self) { category in
                        Menu(category.title) {
                            ForEach(ExerciseLibrary.all.filter { $0.category == category }) { e in
                                Button(e.name.text) { append(e) }
                            }
                        }
                    }
                } label: {
                    Label(tr("添加动作", "Add exercise"), systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Button(tr("取消", "Cancel")) { dismiss() }
                Button(tr("保存", "Save")) {
                    content.save(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            }
            .padding(16)
        }
        .frame(width: 600, height: 600)
    }

    private func itemRow(_ item: CustomRoutine.Item) -> some View {
        let e = content.exercise(item.exerciseID)
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundColor(.secondary)
            Image(systemName: e?.symbol ?? "questionmark").foregroundColor(Palette.accent).frame(width: 20)
            Text(e?.name.text ?? tr("（已删除的动作）", "(deleted exercise)"))
            Spacer()
            Stepper(value: seconds(item.id), in: 10...600, step: 5) {
                Text((e?.bilateral ?? false) ? tr("每侧 \(item.seconds) 秒", "\(item.seconds) s / side")
                                             : tr("\(item.seconds) 秒", "\(item.seconds) s"))
                    .monospacedDigit()
                    .frame(minWidth: 80, alignment: .trailing)
            }
            .fixedSize()
            Button {
                draft.items.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(tr("移除", "Remove"))
        }
    }

    private func seconds(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { draft.items.first { $0.id == id }?.seconds ?? 30 },
            set: { value in
                if let i = draft.items.firstIndex(where: { $0.id == id }) { draft.items[i].seconds = value }
            })
    }

    private func append(_ e: Exercise) {
        draft.items.append(CustomRoutine.Item(exerciseID: e.id, seconds: e.defaultSeconds))
    }
}
