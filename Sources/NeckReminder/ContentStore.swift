import Foundation
import NeckReminderCore

/// The user's own exercises and combos, plus when each exercise was last practised (used
/// to vary suggested routines). Stored locally in
/// ~/Library/Application Support/NeckReminder/content.json.
@MainActor
final class ContentStore: ObservableObject {
    @Published private(set) var customExercises: [CustomExercise] = []
    @Published private(set) var customRoutines: [CustomRoutine] = []
    @Published private(set) var lastDone: [String: Date] = [:]

    private struct Stored: Codable {
        var customExercises: [CustomExercise] = []
        var customRoutines: [CustomRoutine] = []
        var lastDone: [String: Date] = [:]
    }

    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("NeckReminder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("content.json")
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            customExercises = stored.customExercises
            customRoutines = stored.customRoutines
            lastDone = stored.lastDone
        }
    }

    // MARK: Exercises

    /// Built-in library followed by the user's own exercises.
    var allExercises: [Exercise] { ExerciseLibrary.all + customExercises.map(\.exercise) }

    func exercise(_ id: String) -> Exercise? {
        if let custom = customExercises.first(where: { $0.exerciseID == id }) { return custom.exercise }
        return ExerciseLibrary.all.first { $0.id == id }
    }

    func customExercise(for exerciseID: String) -> CustomExercise? {
        customExercises.first { $0.exerciseID == exerciseID }
    }

    func save(_ e: CustomExercise) {
        if let i = customExercises.firstIndex(where: { $0.id == e.id }) { customExercises[i] = e } else { customExercises.append(e) }
        persist()
    }

    func delete(_ e: CustomExercise) {
        customExercises.removeAll { $0.id == e.id }
        // Combos keep working without it.
        for i in customRoutines.indices {
            customRoutines[i].items.removeAll { $0.exerciseID == e.exerciseID }
        }
        persist()
    }

    // MARK: Combos

    func routine(for combo: CustomRoutine) -> Routine {
        combo.routine { self.exercise($0) }
    }

    func save(_ r: CustomRoutine) {
        if let i = customRoutines.firstIndex(where: { $0.id == r.id }) { customRoutines[i] = r } else { customRoutines.append(r) }
        persist()
    }

    func delete(_ r: CustomRoutine) {
        customRoutines.removeAll { $0.id == r.id }
        persist()
    }

    /// Append an exercise to a combo (or start a new combo with it).
    @discardableResult
    func add(_ e: Exercise, to comboID: UUID?) -> CustomRoutine {
        let item = CustomRoutine.Item(exerciseID: e.id, seconds: e.defaultSeconds)
        if let comboID, let i = customRoutines.firstIndex(where: { $0.id == comboID }) {
            customRoutines[i].items.append(item)
            persist()
            return customRoutines[i]
        }
        let combo = CustomRoutine(name: tr("我的组合 \(customRoutines.count + 1)", "My combo \(customRoutines.count + 1)"), items: [item])
        customRoutines.append(combo)
        persist()
        return combo
    }

    // MARK: History

    func markDone(_ exerciseID: String) {
        lastDone[exerciseID] = Date()
        persist()
    }

    private func persist() {
        let stored = Stored(customExercises: customExercises, customRoutines: customRoutines, lastDone: lastDone)
        if let data = try? JSONEncoder().encode(stored) { try? data.write(to: url, options: .atomic) }
    }
}
