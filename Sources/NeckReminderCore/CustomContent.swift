import Foundation

/// An exercise the user wrote themselves. It plays in routines like the built-in ones and
/// reuses the same pieces: instructions, timer, side switching and a YouTube demo search.
public struct CustomExercise: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var summary: String
    /// One instruction per line.
    public var steps: [String]
    /// Duration when practised (per side if bilateral).
    public var seconds: Int
    public var bilateral: Bool
    public var standing: Bool
    public var category: ExerciseCategory
    /// YouTube search for the demo video; the name is used when empty.
    public var videoQuery: String

    public init(id: UUID = UUID(), name: String = "", summary: String = "", steps: [String] = [],
                seconds: Int = 30, bilateral: Bool = false, standing: Bool = false,
                category: ExerciseCategory = .neck, videoQuery: String = "") {
        self.id = id
        self.name = name
        self.summary = summary
        self.steps = steps
        self.seconds = seconds
        self.bilateral = bilateral
        self.standing = standing
        self.category = category
        self.videoQuery = videoQuery
    }

    public var exerciseID: String { "custom-\(id.uuidString)" }

    public var exercise: Exercise {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = steps.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let query = videoQuery.trimmingCharacters(in: .whitespaces)
        let dosage = bilateral ? "\(seconds) s × 2" : "\(seconds) s"
        return Exercise(
            id: exerciseID, symbol: "star", category: category,
            name: LText(title, title),
            summary: LText(summary, summary),
            howTo: lines.map { LText($0, $0) },
            dosage: LText(bilateral ? "每侧 \(seconds) 秒" : "\(seconds) 秒", dosage),
            caution: nil, bilateral: bilateral, needsStanding: standing,
            youtubeQuery: query.isEmpty ? title : query,
            defaultSeconds: seconds, isCustom: true)
    }
}

/// "My combo": an ordered list of library (or custom) exercises with durations.
public struct CustomRoutine: Codable, Identifiable, Equatable {
    public struct Item: Codable, Identifiable, Equatable {
        public var id: UUID
        public var exerciseID: String
        /// Seconds (per side if the exercise is bilateral).
        public var seconds: Int

        public init(id: UUID = UUID(), exerciseID: String, seconds: Int) {
            self.id = id
            self.exerciseID = exerciseID
            self.seconds = seconds
        }
    }

    public var id: UUID
    public var name: String
    public var items: [Item]

    public init(id: UUID = UUID(), name: String = "", items: [Item] = []) {
        self.id = id
        self.name = name
        self.items = items
    }

    /// Exercises that no longer exist (a deleted custom exercise) are skipped.
    public func routine(lookup: (String) -> Exercise?) -> Routine {
        let resolved = items.compactMap { item in lookup(item.exerciseID).map { ($0, item.seconds) } }
        let title = name.isEmpty ? LText("我的组合", "My combo") : LText(name, name)
        return ExerciseLibrary.makeRoutine(key: "custom-\(id.uuidString)", minutes: 0, title: title,
                                           subtitle: LText("自定义组合", "Custom combo"), items: resolved)
    }
}
