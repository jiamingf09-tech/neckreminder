import Foundation

/// One observation of the machine, taken every few seconds by the app.
/// Everything here can be read on macOS without any privacy permission
/// (no camera, microphone, accessibility or input-monitoring access).
public struct ActivitySample: Equatable {
    public var date: Date
    /// Seconds since the last hardware input event of any kind (keyboard, mouse move, click, scroll, trackpad).
    public var idleSeconds: TimeInterval
    /// Seconds since the last *deliberate* input: key press, click or scroll.
    /// A mouse that is merely nudged produces "move" events only.
    public var strongIdleSeconds: TimeInterval
    /// Screen locked, display asleep, screen saver running or the login session switched away.
    public var hardAway: Bool
    /// The machine went to sleep since the previous sample.
    public var slept: Bool
    /// A GUI app is holding a "keep the display on" power assertion — typically
    /// video playback or a video call. Used to give passive viewing a longer grace period.
    public var mediaPlaying: Bool
    /// Context-specific grace period (from the learned presence model). Overrides the
    /// fixed reading / media grace when set.
    public var graceOverride: TimeInterval?
    /// When `hardAway` comes from a signal that knows *when* the user left (e.g. their
    /// AirPods walking out of range), the moment they left.
    public var awayHintSince: Date?

    public init(date: Date,
                idleSeconds: TimeInterval,
                strongIdleSeconds: TimeInterval? = nil,
                hardAway: Bool = false,
                slept: Bool = false,
                mediaPlaying: Bool = false,
                graceOverride: TimeInterval? = nil,
                awayHintSince: Date? = nil) {
        self.date = date
        self.idleSeconds = max(0, idleSeconds)
        self.strongIdleSeconds = max(0, strongIdleSeconds ?? idleSeconds)
        self.hardAway = hardAway
        self.slept = slept
        self.mediaPlaying = mediaPlaying
        self.graceOverride = graceOverride
        self.awayHintSince = awayHintSince
    }
}

public enum PresenceState: String, Equatable {
    /// Recent input — the user is definitely at the computer.
    case active
    /// No input for a little while, but not long enough to conclude they left
    /// (reading, watching, thinking). Time spent here is *tentative*.
    case passive
    /// The user is considered away from the computer.
    case away
}

public struct TrackerConfig: Equatable {
    /// Input within this many seconds counts as "active".
    public var activeWindow: TimeInterval = 30
    /// Without input for this long (and no media playing) the user is considered away.
    public var readingGrace: TimeInterval = 180
    /// Grace period used instead while a video / call keeps the display awake.
    public var mediaGrace: TimeInterval = 20 * 60
    /// Being away at least this long counts as a real break and resets the counter.
    public var breakReset: TimeInterval = 5 * 60
    /// Returning from "away" with mouse-movement-only input needs input in this many samples
    /// (a bumped desk or a cat on the trackpad should not end a break).
    /// A key press, click or scroll confirms immediately.
    public var returnConfirmSamples: Int = 2
    /// Mouse-only evidence older than this is forgotten.
    public var returnEvidenceWindow: TimeInterval = 20
    /// Silences at least this long are reported as `GapInfo` when they end.
    public var minReportedGap: TimeInterval = 60

    public init() {}
}

/// Result of feeding one sample into the tracker.
public struct TrackerUpdate: Equatable {
    /// Seconds of use confirmed during this sample (for statistics).
    public var confirmedSeconds: TimeInterval = 0
    /// Tentative (passive) seconds thrown away because the user turned out to be gone.
    public var discardedSeconds: TimeInterval = 0
    /// The away period just became long enough to count as a break; the counter was reset.
    public var breakCompleted = false
    /// The user came back after being away for this long.
    public var returnedAfter: TimeInterval?
    public var stateChanged = false
    /// A silence (no input) of at least `minReportedGap` just ended with new input.
    public var endedGap: GapInfo?

    public init() {}
}

/// A stretch without input that has just ended, and how the tracker accounted for it.
public struct GapInfo: Equatable, Codable {
    /// Last input before the silence.
    public var start: Date
    /// First input after it.
    public var end: Date
    /// true: the silence was counted as use (reading / watching).
    /// false: it was treated as being away.
    public var countedAsPresent: Bool
    /// Being away reset the counter (it counted as a break).
    public var didReset: Bool
    /// Committed use when the absence began (to restore it if the user says they were here).
    public var committedAtStart: TimeInterval
    /// The screen was locked / asleep at some point during the silence.
    public var hadHardAway: Bool

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public init(start: Date, end: Date, countedAsPresent: Bool, didReset: Bool,
                committedAtStart: TimeInterval, hadHardAway: Bool) {
        self.start = start
        self.end = end
        self.countedAsPresent = countedAsPresent
        self.didReset = didReset
        self.committedAtStart = committedAtStart
        self.hadHardAway = hadHardAway
    }
}

/// Estimates how long the user has been *continuously* using the computer.
///
/// The model:
/// * Hardware input (from the HID system, so synthetic events from software don't count)
///   is the only positive evidence of presence. A running build, a download or a
///   playing video never moves the needle on its own.
/// * After the last input the user is first `active`, then `passive` (reading / watching).
///   Passive time is kept *pending* and only committed once input shows up again;
///   if the silence grows past the grace period the pending time is discarded and the
///   user is treated as `away` since the moment of their last input.
/// * Locking the screen, display sleep, screen saver, fast user switching and system
///   sleep are hard "away" signals.
/// * Short absences pause the counter; an absence of at least `breakReset` is a real
///   break and resets it to zero.
/// * Coming back requires believable input (see `returnConfirmSamples`).
public final class UsageTracker {
    public var config: TrackerConfig

    public private(set) var state: PresenceState = .active
    /// Use time that is certain.
    public private(set) var committed: TimeInterval = 0
    /// Use time that is assumed (passive) and will be confirmed or discarded.
    public private(set) var pending: TimeInterval = 0
    /// Start of the current absence (≈ the moment of the last input).
    public private(set) var awaySince: Date?
    public private(set) var lastSampleDate: Date?
    /// Estimated moment of the most recent hardware input.
    public private(set) var lastInputDate: Date?

    public private(set) var isSuspended = false

    private var breakCounted = false
    private var returnEvidence = 0
    private var committedAtAwayStart: TimeInterval = 0
    private var gapHadHardAway = false

    public init(config: TrackerConfig = TrackerConfig()) {
        self.config = config
    }

    /// Best estimate of continuous use right now.
    public var continuousUse: TimeInterval { committed + pending }

    /// Grace period that applies to a sample.
    public func grace(for sample: ActivitySample) -> TimeInterval {
        if let override = sample.graceOverride { return max(config.activeWindow + 1, override) }
        return sample.mediaPlaying ? max(config.readingGrace, config.mediaGrace) : config.readingGrace
    }

    // MARK: - Suspension (e.g. while a relax session runs)

    /// Stop counting. Samples should not be ingested until `resume(at:)`.
    public func suspend() {
        isSuspended = true
        pending = 0
    }

    /// Continue counting from `date` as if the user had just been active; the suspended
    /// interval is not counted either way.
    public func resume(at date: Date) {
        isSuspended = false
        lastSampleDate = date
        lastInputDate = date
        state = .active
        awaySince = nil
        breakCounted = false
        returnEvidence = 0
        gapHadHardAway = false
    }

    // MARK: - Correcting the past (user feedback)

    /// The user says they were at the computer during `gap`: count it.
    public func creditGap(_ gap: GapInfo) {
        guard !gap.countedAsPresent else { return }
        committed += (gap.didReset ? gap.committedAtStart : 0) + gap.duration
    }

    /// The user says they were away during `gap`: stop counting it.
    /// Returns true when the absence was long enough to count as a break (counter reset).
    @discardableResult
    public func debitGap(_ gap: GapInfo) -> Bool {
        guard gap.countedAsPresent else { return false }
        if gap.duration >= config.breakReset {
            // Whatever was done since the gap ended still counts.
            let sinceReturn = lastSampleDate.map { max(0, $0.timeIntervalSince(gap.end)) } ?? 0
            committed = min(committed, sinceReturn)
            pending = 0
            return true
        }
        committed = max(0, committed - gap.duration)
        return false
    }

    /// Start a fresh cycle (user took a break / did the exercises).
    public func reset() {
        committed = 0
        pending = 0
        if state == .away { breakCounted = true }
    }

    @discardableResult
    public func ingest(_ s: ActivitySample) -> TrackerUpdate {
        var update = TrackerUpdate()
        let previousState = state
        defer { update.stateChanged = previousState != state }

        guard let last = lastSampleDate else {
            // First sample: establish the baseline, count nothing.
            lastSampleDate = s.date
            lastInputDate = s.date.addingTimeInterval(-s.idleSeconds)
            if s.hardAway {
                enterAway(since: s.date, &update)
            } else if s.idleSeconds >= grace(for: s) {
                enterAway(since: s.date.addingTimeInterval(-s.idleSeconds), &update)
            } else {
                state = s.idleSeconds <= config.activeWindow ? .active : .passive
            }
            return update
        }

        let dt = s.date.timeIntervalSince(last)
        lastSampleDate = s.date
        let previousInput = lastInputDate
        if !s.slept { lastInputDate = s.date.addingTimeInterval(-s.idleSeconds) }
        guard dt > 0 else { return update } // clock moved backwards; just rebase

        if s.hardAway || s.slept {
            if state != .away {
                // When the machine slept we were not observing; the absence began at the
                // previous sample at the latest. Otherwise it began at the last input
                // (or when an external signal says the user left, if that was later).
                var since = s.slept ? min(last, previousInput ?? last)
                                    : s.date.addingTimeInterval(-s.idleSeconds)
                if let hint = s.awayHintSince, hint > since, hint <= s.date { since = hint }
                enterAway(since: since, &update)
            }
            gapHadHardAway = true
            returnEvidence = 0
            checkBreak(now: s.date, &update)
            return update
        }

        // Did any input happen since the previous sample?
        let freshInput = s.idleSeconds <= dt + 0.5
        let freshStrongInput = s.strongIdleSeconds <= dt + 0.5

        switch state {
        case .away:
            if freshInput {
                returnEvidence += freshStrongInput ? config.returnConfirmSamples : 1
                if returnEvidence >= config.returnConfirmSamples {
                    // Make sure a long absence is credited as a break even if we were
                    // never sampled in between (e.g. tracker resumed after a long pause).
                    let inputMoment = s.date.addingTimeInterval(-min(s.idleSeconds, dt))
                    checkBreak(now: inputMoment, &update)
                    if let since = awaySince {
                        update.returnedAfter = max(0, s.date.timeIntervalSince(since))
                        if inputMoment.timeIntervalSince(since) >= config.minReportedGap {
                            update.endedGap = GapInfo(start: since, end: inputMoment, countedAsPresent: false,
                                                      didReset: breakCounted, committedAtStart: committedAtAwayStart,
                                                      hadHardAway: gapHadHardAway)
                        }
                    }
                    gapHadHardAway = false
                    state = .active
                    awaySince = nil
                    breakCounted = false
                    returnEvidence = 0
                    return update
                }
            } else if s.idleSeconds > config.returnEvidenceWindow {
                returnEvidence = 0
            }
            checkBreak(now: s.date, &update)

        case .active, .passive:
            if freshInput {
                let inputMoment = s.date.addingTimeInterval(-s.idleSeconds)
                if let previousInput, inputMoment.timeIntervalSince(previousInput) >= config.minReportedGap {
                    update.endedGap = GapInfo(start: previousInput, end: inputMoment, countedAsPresent: true,
                                              didReset: false, committedAtStart: committed,
                                              hadHardAway: false)
                }
                // Present: everything since the last sample, plus any tentative time that
                // preceded this input, is confirmed.
                let gained = pending + dt
                committed += gained
                pending = 0
                update.confirmedSeconds = gained
                state = .active
            } else if s.idleSeconds <= config.activeWindow {
                // Very recent input: shown as active, but still only tentative.
                pending += dt
                state = .active
            } else if s.idleSeconds < grace(for: s) {
                pending += dt
                state = .passive
            } else {
                enterAway(since: s.date.addingTimeInterval(-s.idleSeconds), &update)
                checkBreak(now: s.date, &update)
            }
        }
        return update
    }

    private func enterAway(since: Date, _ update: inout TrackerUpdate) {
        update.discardedSeconds += pending
        pending = 0
        state = .away
        awaySince = since
        breakCounted = false
        returnEvidence = 0
        committedAtAwayStart = committed
    }

    private func checkBreak(now: Date, _ update: inout TrackerUpdate) {
        guard state == .away, !breakCounted, let since = awaySince else { return }
        if now.timeIntervalSince(since) >= config.breakReset {
            breakCounted = true
            committed = 0
            pending = 0
            update.breakCompleted = true
        }
    }
}
