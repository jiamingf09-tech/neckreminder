import SwiftUI
import NeckReminderCore

struct LibraryView: View {
    @EnvironmentObject var content: ContentStore
    @EnvironmentObject var session: RelaxSession
    @EnvironmentObject var navigation: Navigation
    @State private var expanded: Set<String> = []
    @State private var video: VideoLink?
    @State private var editingExercise: CustomExercise?
    @State private var editingCombo: CustomRoutine?
    @State private var search = ""
    @State private var note: (id: String, text: String)?

    private func matches(_ e: Exercise) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return [e.name.zh, e.name.en, e.summary.zh, e.summary.en].contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        let custom = content.customExercises.map(\.exercise).filter(matches)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    PageHeader(title: tr("动作库", "Exercise library"),
                               subtitle: tr("\(ExerciseLibrary.all.count + content.customExercises.count) 个动作。可以单独练习、加入自己的组合，或者新建动作。所有动作都应在无痛范围内进行。",
                                            "\(ExerciseLibrary.all.count + content.customExercises.count) exercises. Practise one, add it to a combo, or create your own. Always stay pain-free."))
                    Spacer()
                    Button {
                        editingExercise = CustomExercise()
                    } label: {
                        Label(tr("新建动作", "New exercise"), systemImage: "plus")
                    }
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(tr("搜索动作", "Search exercises"), text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                .frame(maxWidth: 320)

                if !custom.isEmpty {
                    Text(tr("我的动作", "My exercises")).scaledFont(13, weight: .semibold).padding(.top, 4)
                    ForEach(custom) { row($0) }
                }
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    let items = ExerciseLibrary.all.filter { $0.category == category && matches($0) }
                    if !items.isEmpty {
                        Text(category.title).scaledFont(13, weight: .semibold).padding(.top, 4)
                        ForEach(items) { row($0) }
                    }
                }
            }
            .padding(24)
        }
        .sheet(item: $video) { VideoSheet(video: $0) }
        .sheet(item: $editingExercise) { ExerciseEditor(exercise: $0) }
        .sheet(item: $editingCombo) { ComboEditor(combo: $0) }
    }

    private func row(_ e: Exercise) -> some View {
        let isOpen = expanded.contains(e.id)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        if isOpen { expanded.remove(e.id) } else { expanded.insert(e.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: e.symbol)
                                .scaledFont(18)
                                .foregroundColor(Palette.accent)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(e.name.text).scaledFont(13, weight: .semibold)
                                    if e.needsStanding {
                                        Text(tr("站立", "standing"))
                                            .scaledFont(10)
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                                    }
                                }
                                Text(e.dosage.text).scaledFont(10.5).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if let n = note, n.id == e.id {
                        Text(n.text).scaledFont(11).foregroundColor(.green).transition(.opacity)
                    }
                    Button {
                        session.start(ExerciseLibrary.single(e))
                        navigation.section = .relax
                    } label: {
                        Label(tr("练习", "Practise"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    Menu {
                        ForEach(content.customRoutines) { combo in
                            Button(combo.name.isEmpty ? tr("未命名组合", "Untitled combo") : combo.name) {
                                content.add(e, to: combo.id)
                                flash(e.id, tr("已加入「\(combo.name)」", "Added to “\(combo.name)”"))
                            }
                        }
                        if !content.customRoutines.isEmpty { Divider() }
                        Button(tr("新建组合…", "New combo…")) {
                            editingCombo = content.add(e, to: nil)
                        }
                    } label: {
                        Label(tr("加入组合", "Add to combo"), systemImage: "plus.square.on.square")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    if e.isCustom, let custom = content.customExercise(for: e.id) {
                        Button { editingExercise = custom } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help(tr("编辑", "Edit"))
                    }
                }

                if isOpen {
                    if !e.summary.text.isEmpty {
                        Text(e.summary.text).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(e.howTo.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).").foregroundColor(Palette.accent)
                            Text(line.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let caution = e.caution {
                        Label(caution.text, systemImage: "exclamationmark.triangle").foregroundColor(.orange)
                    }
                    Button {
                        video = .youtube(e.name.text, query: e.youtubeQuery)
                    } label: {
                        Label(tr("观看示范视频", "Watch a demo video"), systemImage: "play.rectangle")
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private func flash(_ id: String, _ text: String) {
        withAnimation { note = (id, text) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                if note?.id == id { withAnimation { note = nil } }
            }
        }
    }
}
