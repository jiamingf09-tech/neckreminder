import AppKit

/// Guarantees a single running copy, even when the app is started twice from different
/// paths (e.g. ~/Downloads and /Applications) or with `open -n`.
///
/// The first instance holds an exclusive `flock` on a file for its whole lifetime (released
/// automatically by the kernel when the process exits, even after a crash). A second instance
/// fails to take the lock, asks the first one to show its main window and quits.
enum SingleInstance {
    static let showWindowNotification = Notification.Name("io.github.jiamingf09.NeckReminder.showMainWindow")
    private static var lockDescriptor: Int32 = -1

    static func acquire() -> Bool {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return true }
        let dir = base.appendingPathComponent("NeckReminder", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("instance.lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true } // can't lock: don't block the launch
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockDescriptor = fd
        return true
    }

    static func signalRunningInstance() {
        DistributedNotificationCenter.default().postNotificationName(
            showWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
        if let id = Bundle.main.bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id)
            where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                app.activate(options: [])
            }
        }
    }
}
