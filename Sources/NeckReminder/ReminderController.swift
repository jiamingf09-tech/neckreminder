import AppKit
import Combine
import NeckReminderCore

/// The brain of the app: samples activity, keeps the continuous-use counter, decides when to
/// remind, learns from feedback and reacts to the user's choices.
@MainActor
final class ReminderController: NSObject, ObservableObject {
    @Published private(set) var state: PresenceState = .active
    @Published private(set) var continuousUse: TimeInterval = 0
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var suppression: SuppressionReason?
    @Published private(set) var snapshot: ActivityMonitor.Snapshot?
    @Published private(set) var isRelaxing = false
    /// Current grace period from the presence model (after this much stillness → away).
    @Published private(set) var currentGrace: TimeInterval = 180
    /// Model probability that the user is still here, while they are quiet.
    @Published private(set) var presenceProbability: Double?

    let prefs: Preferences
    let stats: StatsStore
    let notifications: NotificationManager
    let overlay: OverlayController
    let learning: LearningStore
    let feedback: FeedbackPanelController
    let bluetooth: BluetoothProximity
    weak var session: RelaxSession?

    /// Opens the main window on the relax guide.
    var onOpenGuide: (() -> Void)?
    /// Opens the main window on the overview.
    var onOpenMain: (() -> Void)?
    /// Called after every sample (status item refresh).
    var onTick: (() -> Void)?

    private let monitor: ActivityMonitor
    private let tracker: UsageTracker
    private var policy: ReminderPolicy
    private var timer: Timer?
    private var guardTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastSampleWasMedia = false
    private var lastTick: Date?

    // Current silence
    private var gapContext: PresenceContext?
    private var probeShownThisGap = false
    private var probeConfirmed = false
    private var lastProbeAt = Date.distantPast

    // Feedback on the most recent silence can still correct the live counter.
    private var lastEpisodeID: UUID?
    private var lastEpisodeCorrectable = false

    // Relax session
    private var relaxStartedAt: Date?
    private var guardViolation = 0.0

    static let sampleInterval: TimeInterval = 5

    init(prefs: Preferences, stats: StatsStore, notifications: NotificationManager) {
        self.prefs = prefs
        self.stats = stats
        self.notifications = notifications
        self.overlay = OverlayController()
        self.feedback = FeedbackPanelController()
        self.bluetooth = BluetoothProximity()
        self.monitor = ActivityMonitor()
        self.learning = LearningStore(readingGrace: prefs.readingGraceMinutes * 60,
                                      mediaGrace: prefs.mediaExtension ? Double(prefs.mediaGraceMinutes) * 60 : 0)
        self.tracker = UsageTracker(config: prefs.trackerConfig)
        self.policy = ReminderPolicy(interval: Double(prefs.intervalMinutes) * 60,
                                     repeatInterval: Double(prefs.repeatMinutes) * 60)
        super.init()

        bluetooth.address = prefs.bluetoothEnabled ? prefs.bluetoothAddress : nil
        notifications.onAction = { [weak self] action in self?.handle(action) }
        feedback.onAnswer = { [weak self] id, label in self?.answer(id, label) }
        feedback.onNeverAskApp = { [weak self] id in self?.neverAsk(for: id) }
        prefs.objectWillChange
            .sink { [weak self] _ in
                // objectWillChange fires before the new value is stored.
                Task { @MainActor in self?.applyPreferences() }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.sampleInterval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func saveState() {
        stats.save()
        learning.save()
    }

    // MARK: - Sampling

    @objc private func tick() {
        let now = Date()
        let snap = monitor.snapshot()
        snapshot = snap
        lastSampleWasMedia = snap.sample.mediaPlaying
        var sample = snap.sample
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? Self.sampleInterval
        let freshInput = sample.idleSeconds <= dt + 0.5

        // Bluetooth headset walked out of range → away since then, unless there was input after.
        if prefs.bluetoothEnabled {
            bluetooth.poll(now: now)
            if freshInput { bluetooth.userIsBack() }
            if let since = bluetooth.walkedAwaySince, now.addingTimeInterval(-sample.idleSeconds) <= since {
                sample.hardAway = true
                sample.awayHintSince = since
            }
        }

        // Context of the current silence (what was going on while the user was quiet).
        let live = snap.context
        if sample.idleSeconds > tracker.config.activeWindow {
            gapContext = gapContext.map { $0.merged(with: live) } ?? live
        }
        let context = gapContext ?? live

        // Grace from the learned model, or the user's "I'm reading / in a meeting" hold.
        let model = learning.model
        var grace = model.grace(context)
        if let hold = prefs.presenceHoldUntil {
            if hold > now {
                grace = max(grace, hold.timeIntervalSince(now) + sample.idleSeconds)
            } else {
                prefs.presenceHoldUntil = nil
            }
        }
        sample.graceOverride = grace
        currentGrace = grace
        presenceProbability = sample.idleSeconds > tracker.config.activeWindow
            ? model.probabilityPresent(context, after: sample.idleSeconds) : nil

        // Expire one-off suppressions.
        if let until = prefs.pausedUntil, until <= now { prefs.pausedUntil = nil }
        if let day = prefs.ignoredDay, day != DayKey.string(for: now) { prefs.ignoredDay = nil }

        if isRelaxing {
            // The relax session owns this time; the counter is suspended.
            if let last = lastTick { learning.record(.relax, from: last, to: now) }
            lastTick = now
            publish(now: now)
            onTick?()
            return
        }

        // Moving the mouse while the "still there?" hint is up answers it; record that before
        // the silence is processed so the user isn't asked the same thing again.
        if freshInput && feedback.isProbeVisible {
            probeConfirmed = true
            feedback.hideProbe()
        }

        let previousState = tracker.state
        let update = tracker.ingest(sample)
        recordTimeline(previousState: previousState, now: now)
        lastTick = now

        if update.confirmedSeconds > 0 {
            let use = tracker.continuousUse
            stats.update {
                $0.activeSeconds += update.confirmedSeconds
                $0.longestStretch = max($0.longestStretch, use)
            }
        }
        if update.breakCompleted {
            policy.resetCycle()
            stats.update { $0.breaks += 1 }
            // Nobody is there to see a reminder any more.
            overlay.dismiss()
            notifications.clearDelivered()
        }

        if let gap = update.endedGap {
            handleEndedGap(gap, context: gapContext ?? live, snapshot: snap)
            resetSilence()
        } else if freshInput && tracker.state != .away {
            resetSilence()
        }

        updateProbe(snap: snap, sample: sample, context: context, model: model, freshInput: freshInput)

        publish(now: now)
        if shouldFire() { fire() }
        onTick?()
    }

    private func resetSilence() {
        gapContext = nil
        probeShownThisGap = false
        probeConfirmed = false
    }

    private func recordTimeline(previousState: PresenceState, now: Date) {
        guard let last = lastTick else { return }
        let kind: SegmentKind
        switch tracker.state {
        case .active: kind = .active
        case .passive: kind = .passive
        case .away: kind = .away
        }
        learning.record(kind, from: last, to: now)
        // Becoming away rewrites the tentative "reading" time back to the last input.
        if tracker.state == .away, previousState != .away, let since = tracker.awaySince, since < last {
            learning.record(.away, from: since, to: now)
        }
    }

    private func publish(now: Date = Date()) {
        state = tracker.state
        continuousUse = tracker.continuousUse
        remaining = policy.remaining(use: tracker.continuousUse)
        suppression = ReminderGate.suppression(at: now,
                                               enabled: prefs.enabled,
                                               pausedUntil: prefs.pausedUntil,
                                               ignoredDay: prefs.ignoredDay,
                                               rules: prefs.schedule)
    }

    private func shouldFire() -> Bool {
        guard suppression == nil, !isRelaxing, !overlay.isVisible else { return false }
        guard policy.isDue(use: tracker.continuousUse) else { return false }
        // Only remind when there is evidence somebody is looking: recent input, or passive
        // viewing of a video / call. A reminder that comes due while the user is quietly
        // reading waits for their next input instead of popping up to an empty room.
        switch tracker.state {
        case .active: return true
        case .passive: return lastSampleWasMedia
        case .away: return false
        }
    }

    // MARK: - Learning from silences

    private func handleEndedGap(_ gap: GapInfo, context: PresenceContext, snapshot snap: ActivityMonitor.Snapshot) {
        let p = learning.model.probabilityPresent(context, after: gap.duration)
        var episode = GapEpisode(gap: gap, context: context, predicted: p)
        if probeConfirmed {
            episode.label = .present
            episode.source = .probe
        } else if gap.hadHardAway {
            episode.label = .away
            episode.source = .implicit
        } else if gap.countedAsPresent, gap.duration < 600, snap.frontmostID != nil, snap.frontmostID == context.frontAppID {
            // Picked up where they left off in the same app shortly after: most likely reading.
            episode.label = .present
            episode.source = .implicit
        }
        learning.add(episode)
        lastEpisodeID = episode.id
        lastEpisodeCorrectable = true

        guard shouldAsk(episode) else { return }
        if snap.isPresenting || overlay.isVisible || isRelaxing {
            // Don't put a question over a presentation; it waits in the review page.
            learning.markAwaitingReview(episode.id)
        } else {
            learning.markAsked(episode.id, at: Date())
            feedback.ask(episode: episode, scale: prefs.textScale)
        }
    }

    private func shouldAsk(_ e: GapEpisode) -> Bool {
        guard prefs.askOnReturn, e.source != .probe, !e.gap.hadHardAway else { return false }
        guard e.gap.duration >= 120, e.gap.duration <= 45 * 60 else { return false }
        if let app = e.context.appID, prefs.noAskApps.contains(app) { return false }
        guard learning.questionsAsked(on: Date()) < prefs.maxQuestionsPerDay else { return false }
        // Ask only where the model is unsure — a little more freely while it knows little
        // about this app.
        if (0.2...0.8).contains(e.predicted) { return true }
        return learning.userLabels(forApp: e.context.appID) < 3 && (0.08...0.92).contains(e.predicted)
    }

    /// The user said whether they were at the computer during a silence (question panel or
    /// review page). Corrects statistics, the timeline and — for the latest silence — the
    /// live counter, then retrains the model.
    func answer(_ id: UUID, _ label: PresenceLabel) {
        guard let e = learning.episode(id) else { return }
        let wasPresent = e.effectivePresent
        learning.setLabel(id, label, source: .user)
        let nowPresent = label == .present
        guard wasPresent != nowPresent else { return }

        let correctable = id == lastEpisodeID && lastEpisodeCorrectable && !isRelaxing
        let sameDay = Calendar.current.isDateInToday(e.gap.end)
        let duration = e.gap.duration
        if nowPresent {
            if correctable {
                tracker.creditGap(e.gap)
                // Don't fire a reminder the instant the user clicks.
                if policy.isDue(use: tracker.continuousUse) { policy.snooze(60, use: tracker.continuousUse) }
            }
            if sameDay {
                stats.update {
                    $0.activeSeconds += duration
                    if e.gap.didReset { $0.breaks = max(0, $0.breaks - 1) }
                }
            }
            learning.record(.passive, from: e.gap.start, to: e.gap.end)
        } else {
            if correctable, tracker.debitGap(e.gap) { policy.resetCycle() }
            if sameDay {
                stats.update {
                    $0.activeSeconds = max(0, $0.activeSeconds - duration)
                    if duration >= tracker.config.breakReset { $0.breaks += 1 }
                }
            }
            learning.record(.away, from: e.gap.start, to: e.gap.end)
        }
        publish()
        onTick?()
    }

    private func neverAsk(for id: UUID) {
        guard let app = learning.episode(id)?.context.appID, !prefs.noAskApps.contains(app) else { return }
        prefs.noAskApps.append(app)
    }

    // MARK: - "Still there?" hint

    private func updateProbe(snap: ActivityMonitor.Snapshot, sample: ActivitySample, context: PresenceContext,
                             model: PresenceModel, freshInput: Bool) {
        if feedback.isProbeVisible {
            if tracker.state == .away || (feedback.probeAge ?? 0) > 90 {
                feedback.hideProbe()
            }
            return
        }
        guard prefs.probeEnabled, tracker.state == .passive, !probeShownThisGap,
              !snap.isPresenting, !overlay.isVisible, !feedback.isQuestionVisible,
              Date().timeIntervalSince(lastProbeAt) > 10 * 60 else { return }
        let grace = sample.graceOverride ?? currentGrace
        let showAt = model.silence(at: 0.65, context)
        if sample.idleSeconds >= showAt, grace - sample.idleSeconds >= 30 {
            feedback.showProbe(scale: prefs.textScale)
            probeShownThisGap = true
            lastProbeAt = Date()
        }
    }

    // MARK: - Reminding

    private func reminderContent(minutes: Int) -> OverlayContent {
        OverlayContent(
            title: tr("该放松一下颈椎了", "Time to rest your neck"),
            subtitle: tr("你已经连续使用电脑 \(minutes) 分钟，抬起头活动一下肩颈吧。",
                         "You've been at the computer for \(minutes) minutes. Look up and loosen your neck and shoulders."),
            primary: OverlayButton(id: ReminderAction.relax.rawValue, title: tr("放松颈椎", "Relax my neck"), symbol: "figure.mind.and.body"),
            secondary: [
                OverlayButton(id: ReminderAction.snooze5.rawValue, title: tr("5 分钟后提醒", "In 5 min")),
                OverlayButton(id: ReminderAction.snooze10.rawValue, title: tr("10 分钟后提醒", "In 10 min")),
                OverlayButton(id: ReminderAction.skip.rawValue, title: tr("本次忽略", "Skip this time")),
                OverlayButton(id: ReminderAction.skipToday.rawValue, title: tr("今日忽略", "Skip today")),
            ],
            footnote: { s in
                s > 0 ? tr("提醒不会拦截鼠标和键盘，\(s) 秒后自动隐藏", "Mouse and keyboard keep working · hides in \(s)s") : nil
            })
    }

    func fire(preview: Bool = false) {
        let use = tracker.continuousUse
        if !preview {
            policy.markFired(use: use)
            stats.update { $0.reminders += 1 }
        }
        let minutes = max(1, Int(use / 60))
        let content = reminderContent(minutes: minutes)

        let notify = prefs.useNotification && notifications.canDeliver
        if notify {
            notifications.deliver(title: content.title, body: content.subtitle, sound: prefs.notificationSound)
        }
        // Never lose a reminder silently: without working notifications fall back to the overlay.
        var mode = prefs.overlayMode
        if mode == .off && !notify { mode = .activeScreen }
        if mode != .off {
            feedback.hideProbe()
            overlay.show(mode: mode, content: content, opacity: prefs.overlayOpacity,
                         autoHideSeconds: prefs.overlaySeconds) { [weak self] id in
                guard let action = ReminderAction(rawValue: id) else { return }
                self?.handle(action)
            }
        }
        publish()
    }

    func handle(_ action: ReminderAction) {
        let use = tracker.continuousUse
        switch action {
        case .snooze5: policy.snooze(5 * 60, use: use)
        case .snooze10: policy.snooze(10 * 60, use: use)
        case .skip: policy.skipThisTime(use: use)
        case .skipToday:
            prefs.ignoredDay = DayKey.string(for: Date())
            policy.skipThisTime(use: use)
        case .relax:
            notifications.clearDelivered()
            // The counter resets once a session is actually done; until then, give the user
            // time to pick a routine without the reminder coming straight back.
            policy.snooze(10 * 60, use: use)
            overlay.celebrate { [weak self] in self?.onOpenGuide?() }
            publish()
            return
        case .open:
            onOpenMain?()
        }
        overlay.dismiss()
        notifications.clearDelivered()
        publish()
    }

    // MARK: - Breaks & relax sessions

    /// The user says they just took a break.
    func startBreak() {
        tracker.reset()
        policy.resetCycle()
        lastEpisodeCorrectable = false
        publish()
    }

    func relaxSessionStarted() {
        isRelaxing = true
        relaxStartedAt = Date()
        tracker.suspend()
        lastEpisodeCorrectable = false
        overlay.dismiss()
        notifications.clearDelivered()
        feedback.hideProbe()
        feedback.dismissQuestion(answered: true)
        guardViolation = 0
        guardTimer?.invalidate()
        let t = Timer(timeInterval: 1, target: self, selector: #selector(guardTick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        guardTimer = t
        publish()
    }

    func relaxSessionEnded(completed: Bool, activeTime: TimeInterval, totalTime: TimeInterval) {
        let now = Date()
        isRelaxing = false
        guardTimer?.invalidate()
        guardTimer = nil
        if overlay.isVisible { overlay.dismiss() }
        if let start = relaxStartedAt { learning.record(.relax, from: start, to: now) }
        relaxStartedAt = nil

        // A session counts as a break when finished, or when most of it (or 2 minutes) was done.
        let countsAsBreak = completed || activeTime >= min(120, totalTime * 0.5)
        stats.update {
            if completed { $0.relaxSessions += 1 }
            $0.relaxSeconds += activeTime
        }
        if countsAsBreak {
            tracker.reset()
            policy.resetCycle()
        }
        // Cancelled early: the counter simply continues where it was before the session.
        tracker.resume(at: now)
        lastTick = now
        publish()
    }

    /// While a routine runs, typing or clicking in *another* app means the user went back to
    /// work. NeckReminder itself (timer controls, the in-app demo videos) is fine, and so is
    /// not touching the computer at all.
    @objc private func guardTick() {
        guard let session, session.isRunning, !session.isPaused, !overlay.isVisible else {
            guardViolation = 0
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if front == ownPID {
            guardViolation = 0
            return
        }
        let idle = ActivityMonitor.idleSeconds()
        if idle < 1.5 {
            guardViolation += 1
        } else if idle > 5 {
            guardViolation = max(0, guardViolation - 0.5)
        }
        if guardViolation >= 10 {
            guardViolation = 0
            showRelaxGuard()
        }
    }

    private func showRelaxGuard() {
        session?.pause()
        let content = OverlayContent(
            symbol: "hand.raised",
            title: tr("你仍在操作电脑", "You're still at the computer"),
            subtitle: tr("颈椎放松进行到一半，计时已暂停。先放下手头的事，跟着指南做完吧。",
                         "Your neck break is half done and the timer is paused. Set the work aside and finish it."),
            primary: OverlayButton(id: "guard.back", title: tr("回到颈椎放松", "Back to my neck break"), symbol: "arrow.uturn.backward"),
            secondary: [
                OverlayButton(id: "guard.pause", title: tr("暂停颈椎放松", "Pause the break")),
                OverlayButton(id: "guard.cancel", title: tr("取消本次放松", "Cancel this break")),
            ],
            footnote: { s in
                s > 0 ? tr("提醒不会拦截鼠标和键盘，\(s) 秒后自动隐藏（放松保持暂停）",
                           "Mouse and keyboard keep working · hides in \(s)s (break stays paused)") : nil
            })
        let mode: OverlayMode = prefs.overlayMode == .off ? .activeScreen : prefs.overlayMode
        overlay.show(mode: mode, content: content, opacity: prefs.overlayOpacity, autoHideSeconds: 60) { [weak self] id in
            self?.handleGuard(id)
        }
    }

    private func handleGuard(_ id: String) {
        overlay.dismiss()
        switch id {
        case "guard.back":
            session?.resume()
            onOpenGuide?()
        case "guard.cancel":
            session?.stop()
        default:
            break // paused: stays paused until the user resumes it in the app
        }
    }

    // MARK: - Pausing

    func pause(for seconds: TimeInterval) {
        prefs.pausedUntil = Date().addingTimeInterval(seconds)
        publish()
    }

    func pauseUntilTomorrow() {
        prefs.pausedUntil = DayKey.startOfTomorrow(after: Date())
        publish()
    }

    func pauseIndefinitely() {
        prefs.pausedUntil = .distantFuture
        publish()
    }

    func resume() {
        prefs.pausedUntil = nil
        prefs.ignoredDay = nil
        if !prefs.enabled { prefs.enabled = true }
        publish()
    }

    /// "I'm reading / in a meeting": stillness is not treated as being away for a while.
    func holdPresence(minutes: Int) {
        prefs.presenceHoldUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        publish()
    }

    func cancelPresenceHold() {
        prefs.presenceHoldUntil = nil
        publish()
    }

    // MARK: - Preferences

    private func applyPreferences() {
        let config = prefs.trackerConfig
        if tracker.config != config { tracker.config = config }
        learning.updatePrior(readingGrace: prefs.readingGraceMinutes * 60,
                             mediaGrace: prefs.mediaExtension ? Double(prefs.mediaGraceMinutes) * 60 : 0)
        let interval = Double(prefs.intervalMinutes) * 60
        let repeatInterval = Double(prefs.repeatMinutes) * 60
        if interval != policy.interval || repeatInterval != policy.repeatInterval {
            policy.updateIntervals(interval: interval, repeatInterval: repeatInterval, use: tracker.continuousUse)
        }
        let address = prefs.bluetoothEnabled ? prefs.bluetoothAddress : nil
        if bluetooth.address != address { bluetooth.address = address }
        publish()
        onTick?()
    }

    // MARK: - Presentation helpers

    var stateTitle: String {
        if isRelaxing { return tr("正在放松", "Relaxing") }
        switch state {
        case .active: return tr("正在使用", "In use")
        case .passive:
            if prefs.presenceHoldUntil != nil { return tr("阅读 / 开会中（手动）", "Reading / meeting (manual)") }
            return lastSampleWasMedia ? tr("观看中", "Watching") : tr("阅读 / 思考中", "Reading / thinking")
        case .away: return tr("已离开", "Away")
        }
    }

    var suppressionText: String? {
        guard let suppression else { return nil }
        switch suppression {
        case .disabled: return tr("提醒已关闭", "Reminders are off")
        case .paused(let until):
            if until == .distantFuture { return tr("已暂停", "Paused") }
            let f = DateFormatter()
            f.dateStyle = Calendar.current.isDateInToday(until) ? .none : .short
            f.timeStyle = .short
            return tr("已暂停至 \(f.string(from: until))", "Paused until \(f.string(from: until))")
        case .ignoredToday: return tr("今日已忽略提醒", "Skipped for today")
        case .skippedWeekday: return tr("今天是跳过日", "Today is a day off")
        case .quietPeriod(let range): return tr("免打扰时段 \(range.label)", "Quiet hours \(range.label)")
        }
    }
}
