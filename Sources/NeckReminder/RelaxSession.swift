import AppKit
import AVFoundation
import NeckReminderCore

/// Runs a timed routine step by step.
@MainActor
final class RelaxSession: NSObject, ObservableObject {
    @Published private(set) var routine: Routine?
    @Published private(set) var index = 0
    @Published private(set) var stepRemaining: TimeInterval = 0
    @Published private(set) var isPaused = false
    @Published private(set) var finished = false

    var onStarted: (() -> Void)?
    /// `active` = time actually spent on the routine (pauses excluded), `total` = routine length.
    var onEnded: ((_ completed: Bool, _ active: TimeInterval, _ total: TimeInterval) -> Void)?
    var onPauseChanged: ((Bool) -> Void)?

    private let prefs: Preferences
    private var timer: Timer?
    private var stepEnd: Date?
    private var runningSince: Date?
    private var activeTime: TimeInterval = 0
    private let speech = AVSpeechSynthesizer()

    init(prefs: Preferences) {
        self.prefs = prefs
        super.init()
    }

    var isRunning: Bool { routine != nil && !finished }

    var currentStep: RoutineStep? {
        guard let routine, routine.steps.indices.contains(index) else { return nil }
        return routine.steps[index]
    }

    var nextStep: RoutineStep? {
        guard let routine, routine.steps.indices.contains(index + 1) else { return nil }
        return routine.steps[index + 1]
    }

    var totalRemaining: TimeInterval {
        guard let routine else { return 0 }
        let later = routine.steps.dropFirst(index + 1).reduce(0) { $0 + $1.seconds }
        return stepRemaining + TimeInterval(later)
    }

    var overallProgress: Double {
        guard let routine, routine.totalSeconds > 0 else { return 0 }
        return 1 - totalRemaining / TimeInterval(routine.totalSeconds)
    }

    func start(_ routine: Routine) {
        if isRunning { end(completed: false) }
        self.routine = routine
        finished = false
        isPaused = false
        runningSince = Date()
        activeTime = 0
        onStarted?()
        go(to: 0)
        let t = Timer(timeInterval: 0.25, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        stepRemaining = max(0, stepEnd?.timeIntervalSinceNow ?? 0)
        isPaused = true
        if let pausedAt = runningSince { activeTime += Date().timeIntervalSince(pausedAt) }
        runningSince = nil
        onPauseChanged?(true)
    }

    func resume() {
        guard isRunning, isPaused else { return }
        stepEnd = Date().addingTimeInterval(stepRemaining)
        isPaused = false
        runningSince = Date()
        onPauseChanged?(false)
    }

    func next() {
        guard let routine else { return }
        if index + 1 < routine.steps.count { go(to: index + 1) } else { complete() }
    }

    func previous() {
        guard routine != nil else { return }
        go(to: max(0, index - 1))
    }

    /// Stop early.
    func stop() {
        guard routine != nil else { return }
        end(completed: false)
    }

    /// Leave the "finished" screen.
    func close() {
        routine = nil
        finished = false
    }

    private func go(to newIndex: Int) {
        guard let routine, routine.steps.indices.contains(newIndex) else { return }
        index = newIndex
        let step = routine.steps[newIndex]
        stepRemaining = TimeInterval(step.seconds)
        stepEnd = Date().addingTimeInterval(stepRemaining)
        if isPaused {
            isPaused = false
            runningSince = Date()
            onPauseChanged?(false)
        }
        announce(step)
    }

    @objc private func tick() {
        guard isRunning, !isPaused, let stepEnd else { return }
        stepRemaining = max(0, stepEnd.timeIntervalSinceNow)
        if stepRemaining <= 0 { next() }
    }

    private func complete() {
        if prefs.stepChime { NSSound(named: "Glass")?.play() }
        if prefs.voiceGuidance { say(tr("完成！做得很好。", "All done. Great job.")) }
        end(completed: true)
        finished = true
    }

    private func end(completed: Bool) {
        timer?.invalidate()
        timer = nil
        let total = TimeInterval(routine?.totalSeconds ?? 0)
        let elapsed = activeTime + (runningSince.map { Date().timeIntervalSince($0) } ?? 0)
        runningSince = nil
        activeTime = 0
        if !completed {
            routine = nil
            finished = false
            speech.stopSpeaking(at: .immediate)
        }
        onEnded?(completed, elapsed, total)
    }

    private func announce(_ step: RoutineStep) {
        if prefs.stepChime { NSSound(named: "Tink")?.play() }
        if prefs.voiceGuidance {
            var text = step.title
            if let first = step.exercise.howTo.first { text += "。" + first.text }
            say(text)
        }
    }

    private func say(_ text: String) {
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: L10n.isChinese ? "zh-CN" : "en-US")
        speech.speak(utterance)
    }
}
