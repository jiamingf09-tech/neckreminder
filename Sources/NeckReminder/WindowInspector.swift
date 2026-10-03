import AppKit
import CoreGraphics

/// Reads the on-screen window list. Only geometry, layer and owning process are used —
/// window titles and contents (which would need Screen Recording permission) are never
/// touched.
enum WindowInspector {
    struct Result {
        /// The frontmost app has a window covering a whole display (presentation, full-screen video).
        var frontmostFullscreen = false
        /// Processes owning a small always-on-top window that looks like picture in picture.
        var floatingVideoCandidates: [(pid: pid_t, owner: String)] = []
    }

    /// System processes whose floating windows are never a video.
    private static let systemOwners: Set<String> = [
        "Window Server", "Dock", "Control Center", "ControlCenter", "SystemUIServer",
        "Notification Center", "NotificationCenter", "Spotlight", "loginwindow",
        "TextInputMenuAgent", "TextInputSwitcher", "universalAccessAuthWarn", "CursorUIViewService",
        "Screenshot", "screencaptureui", "WindowManager",
    ]

    static func inspect(frontmostPID: pid_t?) -> Result {
        var result = Result()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return result }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let screens = NSScreen.screens.map(\.frame.size)
        let largestArea = screens.map { $0.width * $0.height }.max() ?? 1

        for info in list {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID else { continue }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.2,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""

            if layer == 0, pid == frontmostPID,
               screens.contains(where: { abs($0.width - rect.width) < 2 && abs($0.height - rect.height) < 2 }) {
                result.frontmostFullscreen = true
            }

            // Picture in picture: a small, video-shaped window floating above normal windows.
            guard layer > 0, layer < 20, !systemOwners.contains(owner) else { continue }
            let area = rect.width * rect.height
            let aspect = rect.width / max(rect.height, 1)
            if rect.width >= 160, rect.height >= 90, area <= largestArea * 0.3, aspect >= 0.5, aspect <= 2.6 {
                result.floatingVideoCandidates.append((pid, owner))
            }
        }
        return result
    }

    /// The system picture-in-picture service shows Safari / QuickTime / FaceTime PiP windows.
    static func isSystemPictureInPicture(_ owner: String) -> Bool {
        let o = owner.lowercased()
        return o.contains("pipagent") || o.contains("picture in picture") || o.contains("画中画")
    }
}
