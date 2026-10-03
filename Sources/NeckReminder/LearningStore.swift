import Foundation
import NeckReminderCore

/// Local-only storage for the presence model's training data (silences + answers) and
/// the review timeline. Nothing here leaves the Mac. Stored as JSON in
/// ~/Library/Application Support/NeckReminder/.
@MainActor
final class LearningStore: ObservableObject {
    @Published private(set) var episodes: [GapEpisode] = []
    @Published private(set) var timeline = Timeline()
    @Published private(set) var model: PresenceModel

    private let directory: URL
    private var dirty = false
    private var lastSave = Date.distantPast

    init(readingGrace: TimeInterval, mediaGrace: TimeInterval) {
        model = PresenceModel(readingGrace: readingGrace, mediaGrace: mediaGrace)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("NeckReminder", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        refit()
    }

    // MARK: Episodes

    func add(_ episode: GapEpisode) {
        episodes.append(episode)
        if episodes.count > 3000 { episodes.removeFirst(episodes.count - 3000) }
        if episode.label != nil { refit() }
        markDirty()
    }

    func episode(_ id: UUID) -> GapEpisode? { episodes.first { $0.id == id } }

    func setLabel(_ id: UUID, _ label: PresenceLabel, source: LabelSource) {
        guard let i = episodes.firstIndex(where: { $0.id == id }) else { return }
        // A user answer always wins; weaker sources never overwrite it.
        if episodes[i].source == .user && source != .user { return }
        episodes[i].label = label
        episodes[i].source = source
        episodes[i].awaitingReview = false
        refit()
        markDirty()
    }

    func questionsAsked(on day: Date) -> Int {
        let cal = Calendar.current
        return episodes.filter { $0.askedAt.map { cal.isDate($0, inSameDayAs: day) } ?? false }.count
    }

    func markAsked(_ id: UUID, at date: Date) {
        guard let i = episodes.firstIndex(where: { $0.id == id }) else { return }
        episodes[i].askedAt = date
        markDirty()
    }

    func markAwaitingReview(_ id: UUID) {
        guard let i = episodes.firstIndex(where: { $0.id == id }), episodes[i].source != .user else { return }
        episodes[i].awaitingReview = true
        markDirty()
    }

    func userLabels(forApp appID: String?) -> Int {
        guard let appID else { return 0 }
        return episodes.filter { $0.context.appID == appID && $0.source == .user }.count
    }

    var awaitingReviewCount: Int { episodes.filter { $0.awaitingReview && $0.source != .user }.count }

    // MARK: Model

    func updatePrior(readingGrace: TimeInterval, mediaGrace: TimeInterval) {
        guard model.readingGrace != max(60, readingGrace) || model.mediaGrace != mediaGrace else { return }
        model = PresenceModel(readingGrace: readingGrace, mediaGrace: mediaGrace)
        refit()
    }

    private func refit() {
        var m = model
        m.fit(episodes)
        model = m
    }

    /// Per-app learned grace for apps the user has answered about.
    func learnedApps() -> [(name: String, grace: TimeInterval, answers: Int)] {
        var byApp: [String: (name: String, count: Int)] = [:]
        for e in episodes where e.source == .user {
            guard let id = e.context.appID else { continue }
            byApp[id] = (e.context.appName ?? id, (byApp[id]?.count ?? 0) + 1)
        }
        return byApp.map { id, v in
            (v.name, model.grace(PresenceContext(appID: id)), v.count)
        }
        .sorted { $0.answers > $1.answers }
    }

    // MARK: Timeline

    func record(_ kind: SegmentKind, from: Date, to: Date) {
        timeline.record(kind, from: from, to: to)
        markDirty()
    }

    // MARK: Reset

    func clearAll() {
        episodes = []
        timeline = Timeline()
        refit()
        save()
    }

    // MARK: Persistence

    private var episodesURL: URL { directory.appendingPathComponent("episodes.json") }
    private var timelineURL: URL { directory.appendingPathComponent("timeline.json") }

    private func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: episodesURL),
           let list = try? decoder.decode([GapEpisode].self, from: data) {
            episodes = list
        }
        if let data = try? Data(contentsOf: timelineURL),
           let t = try? decoder.decode(Timeline.self, from: data) {
            timeline = t
        }
    }

    private func markDirty() {
        dirty = true
        if Date().timeIntervalSince(lastSave) > 60 { save() }
    }

    func save() {
        let cutoff = Date().addingTimeInterval(-8 * 86_400)
        timeline.prune(before: cutoff)
        episodes.removeAll { $0.gap.end < Date().addingTimeInterval(-90 * 86_400) }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(episodes) { try? data.write(to: episodesURL, options: .atomic) }
        if let data = try? encoder.encode(timeline) { try? data.write(to: timelineURL, options: .atomic) }
        dirty = false
        lastSave = Date()
    }

    func saveIfNeeded() { if dirty { save() } }
}
