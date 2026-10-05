import AppKit
import AVFoundation
import CoreAudio
import NeckReminderCore

/// "Is the microphone / camera / speaker in use right now?" — the same information behind
/// the orange and green dots in the menu bar. Nothing is recorded or played, and no
/// microphone or camera permission is involved: these are status flags, not the devices.
enum MediaDevices {
    struct Status: Equatable {
        var micInUse = false
        var cameraInUse = false
        var outputActive = false
        /// Apps producing / capturing audio (macOS 14.2+; empty on older systems).
        var outputApps: Set<String> = []
        var inputApps: Set<String> = []
    }

    static func status() -> Status {
        var s = Status()
        let devices = audioDevices()
        s.micInUse = devices.contains { hasStreams($0, input: true) && isRunningSomewhere($0) }
        s.outputActive = devices.contains { hasStreams($0, input: false) && isRunningSomewhere($0) }
        if supportsProcessList {
            // Per-process data is more precise than "the device is running somewhere", and lets
            // us ignore system services (e.g. "Hey Siri" keeping the microphone open).
            let processes = audioProcesses().filter { !isSystemService($0.bundleID) }
            s.outputApps = Set(processes.filter(\.output).map(\.bundleID))
            s.inputApps = Set(processes.filter(\.input).map(\.bundleID))
            s.outputActive = !s.outputApps.isEmpty
            s.micInUse = !s.inputApps.isEmpty
        }
        s.cameraInUse = Camera.shared.inUse()
        return s
    }

    // MARK: CoreAudio devices

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = address(selector)
        guard AudioObjectHasProperty(object, &addr) else { return [] }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func audioDevices() -> [AudioObjectID] {
        objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
    }

    private static func hasStreams(_ device: AudioObjectID, input: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        guard AudioObjectHasProperty(object, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        (uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
    }

    // MARK: CoreAudio process objects (macOS 14.2+)

    // Four-char codes from AudioHardware.h; used raw so the code also builds and runs on
    // systems where the constants don't exist (the property is simply absent there).
    private static let processObjectList = AudioObjectPropertySelector(0x7072_7323) // 'prs#'
    private static let processBundleID = AudioObjectPropertySelector(0x7062_6964)   // 'pbid'
    private static let processPID = AudioObjectPropertySelector(0x7070_6964)          // 'ppid'
    private static let processRunningInput = AudioObjectPropertySelector(0x7069_7269)  // 'piri'
    private static let processRunningOutput = AudioObjectPropertySelector(0x7069_726F) // 'piro'

    private static var supportsProcessList: Bool {
        var addr = address(processObjectList)
        return AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &addr)
    }

    /// Apple apps that do play / capture media on the user's behalf.
    private static let appleMediaApps = ["com.apple.FaceTime", "com.apple.Safari", "com.apple.WebKit",
                                         "com.apple.QuickTimePlayerX", "com.apple.Music", "com.apple.TV",
                                         "com.apple.podcasts", "com.apple.VoiceMemos", "com.apple.PhotoBooth",
                                         "com.apple.iWork.Keynote"]

    private static func isSystemService(_ bundleID: String) -> Bool {
        guard bundleID.hasPrefix("com.apple.") else { return false }
        return !appleMediaApps.contains { bundleID.hasPrefix($0) }
    }

    private struct AudioProcess {
        var bundleID: String
        var input: Bool
        var output: Bool
    }

    /// Audio clients resolved to the *app* they belong to. Background services (audio
    /// routing daemons such as Rogue Amoeba's ARK, dictation, menu bar utilities…) are
    /// dropped: only regular, Dock-visible apps can be in a call or play media.
    private static func audioProcesses() -> [AudioProcess] {
        let ownBundle = Bundle.main.bundleIdentifier
        return objectList(AudioObjectID(kAudioObjectSystemObject), processObjectList).compactMap { object in
            let input = (uint32(object, processRunningInput) ?? 0) != 0
            let output = (uint32(object, processRunningOutput) ?? 0) != 0
            guard input || output else { return nil }
            let pid = uint32(object, processPID).map { pid_t(bitPattern: $0) }
            let reported = string(object, processBundleID)
            guard let id = owningAppBundleID(pid: pid, reported: reported), id != ownBundle else { return nil }
            return AudioProcess(bundleID: id, input: input, output: output)
        }
    }

    private static func owningAppBundleID(pid: pid_t?, reported: String?) -> String? {
        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
            if app.activationPolicy == .regular { return app.bundleIdentifier }
            // A helper (browser renderer, WebKit service…): find the .app it lives in.
            if let path = app.executableURL?.path, let range = path.range(of: ".app/"),
               let id = Bundle(path: String(path[..<range.lowerBound]) + ".app")?.bundleIdentifier,
               NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.activationPolicy == .regular }) {
                return id
            }
        }
        // WebKit media processes report the hosting app's id on some systems.
        if let reported, !reported.isEmpty,
           NSRunningApplication.runningApplications(withBundleIdentifier: reported).contains(where: { $0.activationPolicy == .regular }) {
            return reported
        }
        return nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        guard AudioObjectHasProperty(object, &addr) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    // MARK: Camera

    /// Lists cameras occasionally (cheap) and asks each whether another app is using it.
    /// Listing devices and reading this flag does not require camera permission.
    final class Camera {
        static let shared = Camera()
        private var devices: [AVCaptureDevice] = []
        private var listedAt = Date.distantPast

        func inUse() -> Bool {
            if Date().timeIntervalSince(listedAt) > 60 {
                var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
                if #available(macOS 14.0, *) {
                    types += [.external, .continuityCamera]
                } else {
                    types += [.externalUnknown]
                }
                devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
                listedAt = Date()
            }
            return devices.contains { $0.isInUseByAnotherApplication }
        }
    }
}

/// Meeting apps: microphone + one of these (or an app keeping the display on) = a meeting,
/// not a phone call.
enum MeetingApps {
    static let bundleIDs: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.tencent.meeting",
        "com.tencent.WeWorkMac", "com.alibaba.DingTalkMac", "com.electron.lark", "com.bytedance.lark.Feishu",
        "com.cisco.webexmeetingsapp", "com.webex.meetingmanager", "com.google.Chrome", "com.apple.Safari",
        "com.microsoft.edgemac", "org.mozilla.firefox", "company.thebrowser.Browser", "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
    ]

    static func classify(status: MediaDevices.Status, displayAwakeApps: [String]) -> CallKind {
        if status.cameraInUse { return .video }
        guard status.micInUse else { return .none }
        if !displayAwakeApps.isEmpty || !status.inputApps.isDisjoint(with: bundleIDs) { return .meeting }
        return .voice
    }
}
