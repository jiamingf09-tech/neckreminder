import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import NeckReminderCore

/// Collects the signals used for presence detection. None of these need a privacy permission:
///
/// * `CGEventSource.secondsSinceLastEventType(.hidSystemState, …)` — time since the last
///   hardware input. Unlike an event tap or a global key monitor this does **not** need
///   Accessibility or Input Monitoring access, and it only reports *when*, never *what*.
///   `.hidSystemState` ignores events synthesised by software (remote tools, "mouse jigglers").
/// * Screen lock / screen saver / display sleep / fast-user-switching / system sleep —
///   public notifications plus `CGSessionCopyCurrentDictionary`.
/// * Display-sleep power assertions (`IOPMCopyAssertionsByProcess`) — the same data
///   `pmset -g assertions` shows. A GUI app keeping the display awake is almost always
///   playing video or in a call.
@MainActor
final class ActivityMonitor {
    struct Snapshot {
        var sample: ActivitySample
        var keyIdle: TimeInterval
        var screenLocked: Bool
        var displayAsleep: Bool
        var screenSaver: Bool
        var sessionInactive: Bool
        /// GUI apps keeping the display awake (video, slideshow, call).
        var mediaApps: [String]
        var frontmostID: String?
        var frontmostName: String?
        var frontmostPID: pid_t?
        var frontmostFullscreen: Bool
        var pipApps: [String]
        var devices: MediaDevices.Status
        var call: CallKind
        var recentTyping: Double
        var recentInput: Double

        /// The context used by the presence model.
        var context: PresenceContext {
            let video = !mediaApps.isEmpty
            let pip = !pipApps.isEmpty
            return PresenceContext(appID: frontmostID, appName: frontmostName,
                                   videoPlaying: video, pictureInPicture: pip,
                                   audioOnly: devices.outputActive && !video && !pip,
                                   call: call, frontmostFullscreen: frontmostFullscreen,
                                   recentTyping: recentTyping, recentInput: recentInput)
        }

        /// A presentation or full-screen video is showing: don't put questions on screen.
        var isPresenting: Bool { frontmostFullscreen }
    }

    /// Input history for the last ~5 minutes (one entry per sample): any input / key presses.
    private var recentSamples: [(input: Bool, key: Bool)] = []
    private var lastSampleAt: Date?
    private var cachedContextAt: Date = .distantPast
    private var cachedWindows = WindowInspector.Result()
    private var cachedDevices = MediaDevices.Status()

    private var screenSaverRunning = false
    private var displaysAsleep = false
    private var sessionInactive = false
    private var systemSleeping = false
    private var sleptSinceLastSample = false

    private var cachedMediaApps: [String] = []

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenSaverStarted), name: Notification.Name("com.apple.screensaver.didstart"), object: nil)
        dnc.addObserver(self, selector: #selector(screenSaverStopped), name: Notification.Name("com.apple.screensaver.didstop"), object: nil)
    }

    @objc private func willSleep() { systemSleeping = true; sleptSinceLastSample = true }
    @objc private func didWake() { systemSleeping = false; sleptSinceLastSample = true }
    @objc private func screensDidSleep() { displaysAsleep = true }
    @objc private func screensDidWake() { displaysAsleep = false }
    @objc private func sessionResigned() { sessionInactive = true }
    @objc private func sessionBecameActive() { sessionInactive = false }
    @objc private func screenSaverStarted() { screenSaverRunning = true }
    @objc private func screenSaverStopped() { screenSaverRunning = false }

    func snapshot() -> Snapshot {
        let now = Date()
        let dt = lastSampleAt.map { max(1, now.timeIntervalSince($0)) } ?? 5
        lastSampleAt = now

        let idle = Self.secondsSince(Self.anyInput)
        let keyIdle = Self.secondsSince(.keyDown)
        let strongIdle = [keyIdle] + [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            .map(Self.secondsSince)
        let strong = strongIdle.min() ?? idle

        recentSamples.append((idle <= dt + 0.5, keyIdle <= dt + 0.5))
        if recentSamples.count > 60 { recentSamples.removeFirst(recentSamples.count - 60) }
        let n = Double(max(1, recentSamples.count))
        // Measured over the samples *before* the current silence would be ideal; this is
        // close enough because the silence itself is excluded by the model's time term.
        let recentInput = Double(recentSamples.filter { $0.input }.count) / n
        let recentTyping = Double(recentSamples.filter { $0.key }.count) / n

        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
        let onConsole = (session?["kCGSSessionOnConsoleKey"] as? Bool) ?? true
        let displayAsleep = displaysAsleep || CGDisplayIsAsleep(CGMainDisplayID()) != 0
        let inactive = sessionInactive || !onConsole

        let front = NSWorkspace.shared.frontmostApplication

        // The heavier context checks only matter once the user is quiet; while they are
        // typing, refresh them now and then.
        let contextAge = now.timeIntervalSince(cachedContextAt)
        if (idle > 20 && contextAge > 4) || contextAge > 30 {
            cachedMediaApps = Self.appsKeepingDisplayAwake()
            cachedWindows = WindowInspector.inspect(frontmostPID: front?.processIdentifier)
            cachedDevices = MediaDevices.status()
            cachedContextAt = now
        }

        // Picture in picture: the system PiP window, or a floating window of an app that is
        // playing sound or keeping the display awake.
        var pip: [String] = []
        for candidate in cachedWindows.floatingVideoCandidates {
            let app = NSRunningApplication(processIdentifier: candidate.pid)
            let bundleID = app?.bundleIdentifier ?? ""
            let name = app?.localizedName ?? candidate.owner
            let playing = cachedDevices.outputApps.contains(bundleID) || cachedMediaApps.contains(name)
                || (cachedDevices.outputApps.isEmpty && cachedDevices.outputActive)
            if WindowInspector.isSystemPictureInPicture(candidate.owner) || playing {
                pip.append(name)
            }
        }
        pip = Array(Set(pip)).sorted()

        let sample = ActivitySample(
            date: now,
            idleSeconds: idle,
            strongIdleSeconds: strong,
            hardAway: locked || displayAsleep || screenSaverRunning || inactive || systemSleeping,
            slept: sleptSinceLastSample,
            mediaPlaying: !cachedMediaApps.isEmpty || !pip.isEmpty || cachedDevices.cameraInUse)
        sleptSinceLastSample = false

        return Snapshot(sample: sample,
                        keyIdle: keyIdle,
                        screenLocked: locked,
                        displayAsleep: displayAsleep,
                        screenSaver: screenSaverRunning,
                        sessionInactive: inactive,
                        mediaApps: cachedMediaApps,
                        frontmostID: front?.bundleIdentifier,
                        frontmostName: front?.localizedName,
                        frontmostPID: front?.processIdentifier,
                        frontmostFullscreen: cachedWindows.frontmostFullscreen,
                        pipApps: pip,
                        devices: cachedDevices,
                        call: MeetingApps.classify(status: cachedDevices, displayAwakeApps: cachedMediaApps),
                        recentTyping: recentTyping,
                        recentInput: recentInput)
    }

    /// Seconds since any hardware input (cheap; used by the relax-session guard every second).
    static func idleSeconds() -> TimeInterval { secondsSince(anyInput) }

    // MARK: - Input idle time

    /// `kCGAnyInputEventType` (~0) is not exposed as a case of `CGEventType`.
    private static let anyInput = CGEventType(rawValue: ~UInt32(0))!

    static func secondsSince(_ type: CGEventType) -> TimeInterval {
        let s = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
        return s.isFinite && s >= 0 ? s : .greatestFiniteMagnitude
    }

    // MARK: - Display-sleep assertions

    /// Keep-awake utilities hold display assertions without anyone watching; ignore them.
    private static let keepAwakeMarkers = ["caffeinate", "caffeine", "amphetamine", "keepingyouawake",
                                           "lungo", "theine", "jiggler", "insomnia", "nosleep", "owly", "neckreminder"]

    static func appsKeepingDisplayAwake() -> [String] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byPID = unmanaged?.takeRetainedValue() as NSDictionary? else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var names = Set<String>()
        for (key, value) in byPID {
            guard let pid = (key as? NSNumber)?.int32Value, pid != ownPID,
                  let assertions = value as? [NSDictionary] else { continue }
            let keepsDisplayOn = assertions.contains { a in
                let type = a["AssertType"] as? String ?? ""
                return type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleepAssertion"
            }
            guard keepsDisplayOn else { continue }

            let path = executablePath(pid) ?? ""
            let app = NSRunningApplication(processIdentifier: pid)
            let lowered = (path + " " + (app?.bundleIdentifier ?? "")).lowercased()
            if keepAwakeMarkers.contains(where: { lowered.contains($0) }) { continue }
            // loginwindow and friends are not someone watching a video.
            if path.hasPrefix("/System/Library/CoreServices/") { continue }

            // Count GUI apps and their helpers (browser / Electron helpers live inside the .app,
            // Safari's media playback runs in WebKit XPC services). Command-line tools and
            // system daemons are ignored.
            let isAppRelated = app?.activationPolicy == .regular
                || path.contains(".app/")
                || path.contains("WebKit")
            guard isAppRelated else { continue }

            names.insert(displayName(pid: pid, path: path, app: app))
        }
        return names.sorted()
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func displayName(pid: pid_t, path: String, app: NSRunningApplication?) -> String {
        if let name = app?.localizedName, app?.activationPolicy == .regular { return name }
        // ".../Google Chrome.app/Contents/Frameworks/.../Google Chrome Helper" -> "Google Chrome"
        if let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.lowerBound])
            return (appPath as NSString).lastPathComponent
        }
        if path.contains("WebKit") { return "Safari / WebKit" }
        return app?.localizedName ?? (path as NSString).lastPathComponent
    }
}
