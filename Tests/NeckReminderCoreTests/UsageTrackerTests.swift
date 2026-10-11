import XCTest
@testable import NeckReminderCore

final class UsageTrackerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// Feed samples every `step` seconds. `idleAt` returns seconds since last input at time t.
    @discardableResult
    func run(_ tracker: UsageTracker, from start: TimeInterval, to end: TimeInterval, step: TimeInterval = 5,
             idleAt: (TimeInterval) -> TimeInterval,
             strongIdleAt: ((TimeInterval) -> TimeInterval)? = nil,
             hardAway: Bool = false, media: Bool = false) -> [TrackerUpdate] {
        var updates: [TrackerUpdate] = []
        var t = start
        while t <= end {
            updates.append(tracker.ingest(ActivitySample(
                date: t0.addingTimeInterval(t),
                idleSeconds: idleAt(t),
                strongIdleSeconds: strongIdleAt?(t),
                hardAway: hardAway,
                mediaPlaying: media)))
            t += step
        }
        return updates
    }

    func testContinuousTypingCountsWallTime() {
        let tracker = UsageTracker()
        run(tracker, from: 0, to: 600, idleAt: { _ in 1 })
        XCTAssertEqual(tracker.state, .active)
        XCTAssertEqual(tracker.continuousUse, 600, accuracy: 0.001)
    }

    func testReadingWithoutInputIsPendingThenConfirmed() {
        let tracker = UsageTracker()
        run(tracker, from: 0, to: 300, idleAt: { _ in 1 })
        // Reads for two minutes without touching anything.
        run(tracker, from: 305, to: 420, idleAt: { t in t - 300 })
        XCTAssertEqual(tracker.state, .passive)
        XCTAssertGreaterThan(tracker.pending, 0)
        // Scrolls: the reading time is confirmed.
        tracker.ingest(ActivitySample(date: t0.addingTimeInterval(425), idleSeconds: 1))
        XCTAssertEqual(tracker.state, .active)
        XCTAssertEqual(tracker.pending, 0)
        XCTAssertEqual(tracker.continuousUse, 425, accuracy: 0.001)
    }

    func testWalkingAwayDiscardsPassiveTimeAndPauses() {
        var config = TrackerConfig()
        config.readingGrace = 180
        config.breakReset = 300
        let tracker = UsageTracker(config: config)
        run(tracker, from: 0, to: 600, idleAt: { _ in 1 }) // 10 min of work, last input at ~600
        // Leaves (a long build keeps running, but there is no input). Watch for 4 minutes.
        let updates = run(tracker, from: 605, to: 840, idleAt: { t in t - 600 })
        XCTAssertEqual(tracker.state, .away)
        XCTAssertFalse(updates.contains { $0.breakCompleted })
        // The tentative reading time was thrown away: we are back at ~10 minutes.
        XCTAssertEqual(tracker.continuousUse, 600, accuracy: 10)
        XCTAssertNotNil(tracker.awaySince)
    }

    func testLongAbsenceIsABreakAndResets() {
        let tracker = UsageTracker()
        run(tracker, from: 0, to: 1200, idleAt: { _ in 1 })
        let updates = run(tracker, from: 1205, to: 1600, idleAt: { t in t - 1200 })
        XCTAssertEqual(updates.filter { $0.breakCompleted }.count, 1, "break must be reported exactly once")
        XCTAssertEqual(tracker.continuousUse, 0)
        // Comes back and types.
        run(tracker, from: 1605, to: 1665, idleAt: { _ in 1 })
        XCTAssertEqual(tracker.state, .active)
        XCTAssertLessThan(tracker.continuousUse, 70)
    }

    func testLeavingRestartsTheCount() {
        // Default: leaving for a few minutes ends the continuous stretch.
        let tracker = UsageTracker()
        _ = run(tracker, from: 0, to: 900, idleAt: { _ in 1 })
        let updates = run(tracker, from: 905, to: 1140, idleAt: { t in t - 900 })
        XCTAssertTrue(updates.contains { $0.breakCompleted })
        run(tracker, from: 1145, to: 1200, idleAt: { _ in 1 })
        XCTAssertLessThan(tracker.continuousUse, 70)
    }

    func testShortAbsencePausesWithoutResetWhenThresholdIsLonger() {
        var config = TrackerConfig()
        config.breakReset = 300
        let tracker = UsageTracker(config: config)
        run(tracker, from: 0, to: 900, idleAt: { _ in 1 })
        // Away for 4 minutes (grace 3, reset 5).
        run(tracker, from: 905, to: 1140, idleAt: { t in t - 900 })
        XCTAssertEqual(tracker.state, .away)
        run(tracker, from: 1145, to: 1200, idleAt: { _ in 1 })
        XCTAssertEqual(tracker.state, .active)
        XCTAssertGreaterThan(tracker.continuousUse, 900)
        XCTAssertLessThan(tracker.continuousUse, 1000)
    }

    func testScreenLockIsImmediateAway() {
        let tracker = UsageTracker()
        run(tracker, from: 0, to: 600, idleAt: { _ in 1 })
        let updates = run(tracker, from: 605, to: 1000, idleAt: { t in t - 600 }, hardAway: true)
        XCTAssertEqual(tracker.state, .away)
        XCTAssertTrue(updates.contains { $0.breakCompleted })
        XCTAssertEqual(tracker.continuousUse, 0)
    }

    func testMediaPlaybackExtendsGrace() {
        let tracker = UsageTracker()
        run(tracker, from: 0, to: 300, idleAt: { _ in 1 })
        // Watches a video for 10 minutes without touching anything.
        run(tracker, from: 305, to: 900, idleAt: { t in t - 300 }, media: true)
        XCTAssertEqual(tracker.state, .passive)
        XCTAssertEqual(tracker.continuousUse, 900, accuracy: 1)
        // Without media the same silence means away.
        let other = UsageTracker()
        run(other, from: 0, to: 300, idleAt: { _ in 1 })
        run(other, from: 305, to: 900, idleAt: { t in t - 300 }, media: false)
        XCTAssertEqual(other.state, .away)
    }

    func testSingleMouseBumpDoesNotEndABreak() {
        var config = TrackerConfig()
        config.breakReset = 300
        let tracker = UsageTracker(config: config)
        run(tracker, from: 0, to: 300, idleAt: { _ in 1 })
        run(tracker, from: 305, to: 500, idleAt: { t in t - 300 })
        XCTAssertEqual(tracker.state, .away)
        // Desk bumped at t = 502: one mouse-move event, no clicks / keys.
        tracker.ingest(ActivitySample(date: t0.addingTimeInterval(505), idleSeconds: 3, strongIdleSeconds: 205))
        XCTAssertEqual(tracker.state, .away)
        // Nothing afterwards; the break continues and completes.
        let updates = run(tracker, from: 510, to: 700, idleAt: { t in t - 502 }, strongIdleAt: { t in t - 300 })
        XCTAssertEqual(tracker.state, .away)
        XCTAssertTrue(updates.contains { $0.breakCompleted })
    }

    func testKeyPressEndsAwayImmediately() {
        let tracker = UsageTracker()
        run(tracker, from: 0, to: 300, idleAt: { _ in 1 })
        run(tracker, from: 305, to: 500, idleAt: { t in t - 300 })
        let u = tracker.ingest(ActivitySample(date: t0.addingTimeInterval(505), idleSeconds: 1, strongIdleSeconds: 1))
        XCTAssertEqual(tracker.state, .active)
        XCTAssertNotNil(u.returnedAfter)
    }

    func testSleepGapIsAway() {
        let tracker = UsageTracker()
        run(tracker, from: 0, to: 600, idleAt: { _ in 1 })
        // Lid closed for an hour; first sample after wake.
        let u = tracker.ingest(ActivitySample(date: t0.addingTimeInterval(4200), idleSeconds: 2, slept: true))
        XCTAssertTrue(u.breakCompleted)
        XCTAssertEqual(tracker.continuousUse, 0)
        run(tracker, from: 4205, to: 4260, idleAt: { _ in 1 })
        XCTAssertEqual(tracker.state, .active)
    }

    func testManualReset() {
        let tracker = UsageTracker()
        run(tracker, from: 0, to: 600, idleAt: { _ in 1 })
        tracker.reset()
        XCTAssertEqual(tracker.continuousUse, 0)
        run(tracker, from: 605, to: 660, idleAt: { _ in 1 })
        XCTAssertEqual(tracker.continuousUse, 60, accuracy: 0.001)
    }
}

final class ReminderPolicyTests: XCTestCase {
    func testCycle() {
        var p = ReminderPolicy(interval: 1800, repeatInterval: 600)
        XCTAssertFalse(p.isDue(use: 1799))
        XCTAssertTrue(p.isDue(use: 1800))
        p.markFired(use: 1800)
        XCTAssertEqual(p.nextDue, 2400)
        p.snooze(300, use: 1900)
        XCTAssertEqual(p.nextDue, 2200)
        p.skipThisTime(use: 2200)
        XCTAssertEqual(p.nextDue, 4000)
        p.resetCycle()
        XCTAssertEqual(p.nextDue, 1800)
    }

    func testChangingIntervalDoesNotFireImmediately() {
        var p = ReminderPolicy(interval: 1800, repeatInterval: 600)
        p.updateIntervals(interval: 900, repeatInterval: 600, use: 1200)
        XCTAssertFalse(p.isDue(use: 1200))
        XCTAssertTrue(p.isDue(use: 1260))
    }
}

final class ScheduleTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testOvernightRange() {
        let r = TimeRange(startMinute: 22 * 60, endMinute: 7 * 60)
        XCTAssertTrue(r.contains(minuteOfDay: 23 * 60))
        XCTAssertTrue(r.contains(minuteOfDay: 6 * 60 + 59))
        XCTAssertFalse(r.contains(minuteOfDay: 7 * 60))
        XCTAssertFalse(r.contains(minuteOfDay: 12 * 60))
    }

    func testGate() {
        // 2026-10-03 is a Saturday.
        let sat = date(2026, 10, 3, 10, 0)
        var rules = ScheduleRules(skippedWeekdays: [7])
        XCTAssertEqual(ReminderGate.suppression(at: sat, enabled: true, pausedUntil: nil, ignoredDay: nil, rules: rules, calendar: calendar), .skippedWeekday)
        rules.skippedWeekdays = []
        let lunch = TimeRange(startMinute: 12 * 60, endMinute: 13 * 60 + 30)
        rules.quietPeriods = [lunch]
        XCTAssertNil(ReminderGate.suppression(at: sat, enabled: true, pausedUntil: nil, ignoredDay: nil, rules: rules, calendar: calendar))
        XCTAssertEqual(ReminderGate.suppression(at: date(2026, 10, 3, 12, 30), enabled: true, pausedUntil: nil, ignoredDay: nil, rules: rules, calendar: calendar), .quietPeriod(lunch))
        XCTAssertEqual(ReminderGate.suppression(at: sat, enabled: true, pausedUntil: nil, ignoredDay: "2026-10-03", rules: rules, calendar: calendar), .ignoredToday)
        XCTAssertNil(ReminderGate.suppression(at: sat, enabled: true, pausedUntil: nil, ignoredDay: "2026-10-02", rules: rules, calendar: calendar))
        let until = sat.addingTimeInterval(3600)
        XCTAssertEqual(ReminderGate.suppression(at: sat, enabled: true, pausedUntil: until, ignoredDay: nil, rules: rules, calendar: calendar), .paused(until: until))
        XCTAssertEqual(ReminderGate.suppression(at: sat, enabled: false, pausedUntil: nil, ignoredDay: nil, rules: rules, calendar: calendar), .disabled)
    }
}

final class ExerciseLibraryTests: XCTestCase {
    func testRoutinesMatchTheirLength() {
        XCTAssertEqual(ExerciseLibrary.routines.map(\.minutes), [2, 5, 10, 15, 30])
        for r in ExerciseLibrary.routines {
            XCTAssertEqual(r.totalSeconds, r.minutes * 60, "routine \(r.minutes) min")
            XCTAssertFalse(r.steps.isEmpty)
        }
    }

    func testExerciseIdsUnique() {
        let ids = ExerciseLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testYoutubeURL() {
        let url = youtubeSearchURL("chin tuck & stretch")
        XCTAssertEqual(url.host, "www.youtube.com")
        XCTAssertTrue(url.absoluteString.contains("search_query="))
        XCTAssertFalse(url.absoluteString.contains(" "))
    }
}
