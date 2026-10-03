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
        var screenLocked: Bool
        var displayAsleep: Bool
        var screenSaver: Bool
        var sessionInactive: Bool
        var mediaApps: [String]
    }

    private var screenSaverRunning = false
    private var displaysAsleep = false
    private var sessionInactive = false
    private var systemSleeping = false
    private var sleptSinceLastSample = false

    private var cachedMediaApps: [String] = []
    private var mediaCheckedAt: Date = .distantPast

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

    func snapshot(grace: TimeInterval) -> Snapshot {
        let now = Date()
        let idle = Self.secondsSince(Self.anyInput)
        let strongIdle = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            .map(Self.secondsSince)
            .min() ?? idle

        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
        let onConsole = (session?["kCGSSessionOnConsoleKey"] as? Bool) ?? true
        let displayAsleep = displaysAsleep || CGDisplayIsAsleep(CGMainDisplayID()) != 0
        let inactive = sessionInactive || !onConsole

        // Media assertions only matter once the user has been quiet for a while; skip the
        // IOKit call otherwise and cache it briefly.
        if idle > 25 {
            if now.timeIntervalSince(mediaCheckedAt) > 15 {
                cachedMediaApps = Self.appsKeepingDisplayAwake()
                mediaCheckedAt = now
            }
        } else {
            cachedMediaApps = []
            mediaCheckedAt = .distantPast
        }

        let sample = ActivitySample(
            date: now,
            idleSeconds: idle,
            strongIdleSeconds: strongIdle,
            hardAway: locked || displayAsleep || screenSaverRunning || inactive || systemSleeping,
            slept: sleptSinceLastSample,
            mediaPlaying: !cachedMediaApps.isEmpty)
        sleptSinceLastSample = false

        return Snapshot(sample: sample,
                        screenLocked: locked,
                        displayAsleep: displayAsleep,
                        screenSaver: screenSaverRunning,
                        sessionInactive: inactive,
                        mediaApps: cachedMediaApps)
    }

    // MARK: - Input idle time

    /// `kCGAnyInputEventType` (~0) is not exposed as a case of `CGEventType`.
    private static let anyInput = CGEventType(rawValue: ~UInt32(0))!

    private static func secondsSince(_ type: CGEventType) -> TimeInterval {
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
