import AppKit
import Combine
import NeckReminderCore

/// The brain of the app: samples activity, keeps the continuous-use counter, decides when to
/// remind and reacts to the user's choice.
@MainActor
final class ReminderController: NSObject, ObservableObject {
    @Published private(set) var state: PresenceState = .active
    @Published private(set) var continuousUse: TimeInterval = 0
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var suppression: SuppressionReason?
    @Published private(set) var snapshot: ActivityMonitor.Snapshot?
    @Published private(set) var isRelaxing = false

    let prefs: Preferences
    let stats: StatsStore
    let notifications: NotificationManager
    let overlay: OverlayController

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
    private var cancellables = Set<AnyCancellable>()
    private var lastSampleWasMedia = false

    static let sampleInterval: TimeInterval = 5

    init(prefs: Preferences, stats: StatsStore, notifications: NotificationManager) {
        self.prefs = prefs
        self.stats = stats
        self.notifications = notifications
        self.overlay = OverlayController()
        self.monitor = ActivityMonitor()
        self.tracker = UsageTracker(config: prefs.trackerConfig)
        self.policy = ReminderPolicy(interval: Double(prefs.intervalMinutes) * 60,
                                     repeatInterval: Double(prefs.repeatMinutes) * 60)
        super.init()

        notifications.onAction = { [weak self] action in self?.handle(action) }
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

    // MARK: - Sampling

    @objc private func tick() {
        let now = Date()
        let snap = monitor.snapshot(grace: tracker.config.readingGrace)
        snapshot = snap
        lastSampleWasMedia = snap.sample.mediaPlaying

        let update = tracker.ingest(snap.sample)
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

        // Expire one-off suppressions.
        if let until = prefs.pausedUntil, until <= now { prefs.pausedUntil = nil }
        if let day = prefs.ignoredDay, day != DayKey.string(for: now) { prefs.ignoredDay = nil }

        publish(now: now)

        if shouldFire() { fire() }
        onTick?()
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

    // MARK: - Reminding

    func fire(preview: Bool = false) {
        let use = tracker.continuousUse
        if !preview {
            policy.markFired(use: use)
            stats.update { $0.reminders += 1 }
        }
        let minutes = max(1, Int(use / 60))
        let title = tr("该放松一下颈椎了", "Time to rest your neck")
        let body = tr("你已经连续使用电脑 \(minutes) 分钟，抬起头活动一下肩颈吧。",
                      "You've been at the computer for \(minutes) minutes. Look up and loosen your neck and shoulders.")

        let notify = prefs.useNotification && notifications.canDeliver
        if notify {
            notifications.deliver(title: title, body: body, sound: prefs.notificationSound)
        }
        // Never lose a reminder silently: without working notifications fall back to the overlay.
        var mode = prefs.overlayMode
        if mode == .off && !notify { mode = .activeScreen }
        if mode != .off {
            overlay.show(mode: mode, title: title, subtitle: body, opacity: prefs.overlayOpacity,
                         autoHideSeconds: prefs.overlaySeconds) { [weak self] action in
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
            startBreak()
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
        publish()
    }

    func relaxSessionStarted() {
        isRelaxing = true
        overlay.dismiss()
        notifications.clearDelivered()
        startBreak()
    }

    func relaxSessionEnded(completed: Bool, elapsed: TimeInterval) {
        isRelaxing = false
        stats.update {
            if completed { $0.relaxSessions += 1 }
            $0.relaxSeconds += elapsed
        }
        startBreak()
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

    // MARK: - Preferences

    private func applyPreferences() {
        let config = prefs.trackerConfig
        if tracker.config != config { tracker.config = config }
        let interval = Double(prefs.intervalMinutes) * 60
        let repeatInterval = Double(prefs.repeatMinutes) * 60
        if interval != policy.interval || repeatInterval != policy.repeatInterval {
            policy.updateIntervals(interval: interval, repeatInterval: repeatInterval, use: tracker.continuousUse)
        }
        publish()
        onTick?()
    }

    // MARK: - Presentation helpers

    var stateTitle: String {
        if isRelaxing { return tr("正在放松", "Relaxing") }
        switch state {
        case .active: return tr("正在使用", "In use")
        case .passive: return lastSampleWasMedia ? tr("观看中", "Watching") : tr("阅读 / 思考中", "Reading / thinking")
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
