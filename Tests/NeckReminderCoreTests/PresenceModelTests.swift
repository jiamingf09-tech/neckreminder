import XCTest
@testable import NeckReminderCore

final class PresenceModelTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testPriorReproducesSettings() {
        let model = PresenceModel(readingGrace: 180, mediaGrace: 1200)
        XCTAssertEqual(model.grace(PresenceContext()), 180, accuracy: 1)
        XCTAssertEqual(model.grace(PresenceContext(videoPlaying: true)), 1200, accuracy: 1)
        XCTAssertEqual(model.grace(PresenceContext(pictureInPicture: true)), 1200, accuracy: 1)
        XCTAssertEqual(model.grace(PresenceContext(call: .video)), 45 * 60, accuracy: 1)
        // Music alone is not a reason to wait longer.
        XCTAssertEqual(model.grace(PresenceContext(audioOnly: true)), 180, accuracy: 1)
        // Voice calls don't need the screen.
        XCTAssertLessThan(model.grace(PresenceContext(call: .voice)), 180)
        XCTAssertEqual(model.probabilityPresent(PresenceContext(), after: 180), 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(model.probabilityPresent(PresenceContext(), after: 60), 0.5)
    }

    func testMediaExtensionDisabled() {
        let model = PresenceModel(readingGrace: 180, mediaGrace: 0)
        XCTAssertEqual(model.grace(PresenceContext(videoPlaying: true)), 180, accuracy: 1)
    }

    func gap(_ minutes: Double, at offset: TimeInterval, counted: Bool) -> GapInfo {
        GapInfo(start: t0.addingTimeInterval(offset), end: t0.addingTimeInterval(offset + minutes * 60),
                countedAsPresent: counted, didReset: false, committedAtStart: 0, hadHardAway: false)
    }

    func testLearnsLongerGraceForAppWhereUserReads() {
        var model = PresenceModel(readingGrace: 180, mediaGrace: 1200)
        let ppt = PresenceContext(appID: "com.microsoft.Powerpoint")
        let finder = PresenceContext(appID: "com.apple.finder")
        var episodes: [GapEpisode] = []
        for i in 0..<8 {
            episodes.append(GapEpisode(gap: gap(9, at: Double(i) * 3600, counted: false), context: ppt,
                                       label: .present, source: .user, predicted: 0.2))
            episodes.append(GapEpisode(gap: gap(6, at: Double(i) * 3600 + 1800, counted: false), context: finder,
                                       label: .away, source: .user, predicted: 0.2))
        }
        model.fit(episodes)
        XCTAssertGreaterThan(model.grace(ppt), 9 * 60, "PowerPoint silences should now be read as reading")
        XCTAssertLessThan(model.grace(finder), 6 * 60)
        // An app the model has never seen stays close to the settings.
        let other = PresenceContext(appID: "com.example.unknown")
        XCTAssertEqual(model.grace(other), 180, accuracy: 120)
    }

    func testFewAnswersOnlyNudge() {
        var model = PresenceModel(readingGrace: 180, mediaGrace: 1200)
        let app = PresenceContext(appID: "com.example.reader")
        model.fit([GapEpisode(gap: gap(20, at: 0, counted: false), context: app,
                              label: .present, source: .implicit, predicted: 0.1)])
        let g = model.grace(app)
        XCTAssertGreaterThan(g, 180)
        XCTAssertLessThan(g, 20 * 60)
    }

    func testSummaryDoesNotClaimTheFrontAppWhenSomethingElseIsPlaying() {
        L10n.language = .zh
        defer { L10n.language = .system }
        let video = PresenceContext(appID: "com.google.Chrome", appName: "Chrome", focus: .video,
                                    frontAppID: "com.microsoft.Powerpoint", frontAppName: "PowerPoint", videoPlaying: true)
        XCTAssertEqual(video.summary, "Chrome 在播放视频（前台：PowerPoint）")
        let plain = PresenceContext(appID: "com.apple.finder", appName: "Finder", focus: .frontmost)
        XCTAssertEqual(plain.summary, "前台应用：Finder")
        XCTAssertEqual(plain.frontAppID, "com.apple.finder")
        XCTAssertNil(PresenceContext().summary)
    }

    func testAccuracy() {
        let e1 = GapEpisode(gap: gap(5, at: 0, counted: true), context: PresenceContext(), label: .present, source: .user, predicted: 0.8)
        let e2 = GapEpisode(gap: gap(5, at: 0, counted: true), context: PresenceContext(), label: .away, source: .user, predicted: 0.8)
        let e3 = GapEpisode(gap: gap(5, at: 0, counted: true), context: PresenceContext(), label: .away, source: .implicit, predicted: 0.8)
        let a = PresenceModel.accuracy([e1, e2, e3])
        XCTAssertEqual(a.correct, 1)
        XCTAssertEqual(a.total, 2)
    }
}

final class TrackerGapTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func sample(_ t: TimeInterval, idle: TimeInterval, grace: TimeInterval? = nil, hardAway: Bool = false) -> ActivitySample {
        ActivitySample(date: t0.addingTimeInterval(t), idleSeconds: idle, graceOverride: grace,
                       awayHintSince: nil).with(hardAway: hardAway)
    }

    func feed(_ tracker: UsageTracker, _ from: TimeInterval, _ to: TimeInterval, idle: (TimeInterval) -> TimeInterval,
              grace: TimeInterval? = nil, hardAway: Bool = false) -> [TrackerUpdate] {
        stride(from: from, through: to, by: 5).map { tracker.ingest(sample($0, idle: idle($0), grace: grace, hardAway: hardAway)) }
    }

    func testReadingGapIsReportedAndCanBeDebited() {
        let tracker = UsageTracker()
        _ = feed(tracker, 0, 600, idle: { _ in 1 })
        _ = feed(tracker, 605, 750, idle: { $0 - 600 })           // 2.5 min reading
        let updates = feed(tracker, 755, 760, idle: { _ in 1 })
        guard let gap = updates.compactMap(\.endedGap).first else { return XCTFail("no gap reported") }
        XCTAssertTrue(gap.countedAsPresent)
        XCTAssertEqual(gap.duration, 154, accuracy: 6)
        let before = tracker.continuousUse
        XCTAssertFalse(tracker.debitGap(gap))
        XCTAssertEqual(tracker.continuousUse, before - gap.duration, accuracy: 0.001)
    }

    func testAwayGapCanBeCreditedEvenAfterReset() {
        let tracker = UsageTracker()
        _ = feed(tracker, 0, 1200, idle: { _ in 1 })                // 20 min of work
        _ = feed(tracker, 1205, 1740, idle: { $0 - 1200 })          // 9 min silence → away + break reset
        XCTAssertEqual(tracker.continuousUse, 0)
        let updates = feed(tracker, 1745, 1750, idle: { _ in 1 })
        guard let gap = updates.compactMap(\.endedGap).first else { return XCTFail("no gap reported") }
        XCTAssertFalse(gap.countedAsPresent)
        XCTAssertTrue(gap.didReset)
        tracker.creditGap(gap)
        // 20 min before + ~9 min of "reading" + the few seconds since.
        XCTAssertEqual(tracker.continuousUse, 1200 + gap.duration + 5, accuracy: 10)
    }

    func testGraceOverrideFromModel() {
        let tracker = UsageTracker()
        _ = feed(tracker, 0, 300, idle: { _ in 1 })
        _ = feed(tracker, 305, 900, idle: { $0 - 300 }, grace: 15 * 60)
        XCTAssertEqual(tracker.state, .passive)
    }

    func testSuspendAndResume() {
        let tracker = UsageTracker()
        _ = feed(tracker, 0, 600, idle: { _ in 1 })
        tracker.suspend()
        tracker.resume(at: t0.addingTimeInterval(900))
        _ = feed(tracker, 905, 960, idle: { _ in 1 })
        XCTAssertEqual(tracker.continuousUse, 600 + 60, accuracy: 0.001)
    }

    func testRelaxSessionIsNotReportedAsSilence() {
        let tracker = UsageTracker()
        _ = feed(tracker, 0, 600, idle: { _ in 1 })
        // A 2-minute routine without touching the computer, then the session ends.
        tracker.suspend()
        tracker.resume(at: t0.addingTimeInterval(725))
        // The system still says "no input since t = 600"; the user comes back at t = 760.
        var updates = feed(tracker, 730, 755, idle: { $0 - 600 })
        updates += feed(tracker, 760, 765, idle: { _ in 1 })
        XCTAssertNil(updates.compactMap(\.endedGap).first, "the routine must not count as a silence")
        XCTAssertEqual(tracker.state, .active)
    }

    func testAwayHintMovesStartOfAbsence() {
        let tracker = UsageTracker()
        _ = feed(tracker, 0, 600, idle: { _ in 1 })
        let hint = t0.addingTimeInterval(640)
        tracker.ingest(ActivitySample(date: t0.addingTimeInterval(700), idleSeconds: 100, hardAway: true, awayHintSince: hint))
        XCTAssertEqual(tracker.state, .away)
        XCTAssertEqual(tracker.awaySince, hint)
    }
}

final class TimelineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    func d(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testRecordMergesAndOverwrites() {
        var tl = Timeline()
        tl.record(.active, from: d(0), to: d(5))
        tl.record(.active, from: d(5), to: d(10))
        tl.record(.passive, from: d(10), to: d(100))
        XCTAssertEqual(tl.segments.count, 2)
        // The silence turned out to be an absence from t = 10.
        tl.record(.away, from: d(10), to: d(200))
        XCTAssertEqual(tl.segments.map(\.kind), [.active, .away])
        // User corrects the middle part: they were reading.
        tl.record(.passive, from: d(50), to: d(80))
        XCTAssertEqual(tl.segments.map(\.kind), [.active, .away, .passive, .away])
        XCTAssertEqual(tl.segments[2].start, d(50))
        XCTAssertEqual(tl.segments[3].end, d(200))
    }
}

private extension ActivitySample {
    func with(hardAway: Bool) -> ActivitySample {
        var s = self
        s.hardAway = hardAway
        return s
    }
}
