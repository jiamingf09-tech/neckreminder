import SwiftUI
import NeckReminderCore

struct LibraryView: View {
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: tr("动作库", "Exercise library"),
                           subtitle: tr("所有动作都应在无痛范围内进行，慢一点、轻一点。",
                                        "Stay pain-free. Slow and gentle beats deep and fast."))
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    let items = ExerciseLibrary.all.filter { $0.category == category }
                    if !items.isEmpty {
                        Text(category.title).font(.headline).padding(.top, 4)
                        ForEach(items) { exercise in
                            row(exercise)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func row(_ e: Exercise) -> some View {
        let isOpen = expanded.contains(e.id)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if isOpen { expanded.remove(e.id) } else { expanded.insert(e.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: e.symbol)
                            .font(.title2)
                            .foregroundColor(Palette.accent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name.text).font(.headline)
                            Text(e.dosage.text).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isOpen {
                    Text(e.summary.text).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(e.howTo.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).").foregroundColor(Palette.accent)
                            Text(line.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let caution = e.caution {
                        Label(caution.text, systemImage: "exclamationmark.triangle").foregroundColor(.orange)
                    }
                    Link(destination: e.youtubeURL) {
                        Label(tr("在 YouTube 查看示范", "Watch a demo on YouTube"), systemImage: "play.rectangle")
                    }
                }
            }
        }
    }
}
