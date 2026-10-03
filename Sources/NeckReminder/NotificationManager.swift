import AppKit
import UserNotifications
import NeckReminderCore

enum ReminderAction: String {
    case snooze5, snooze10, skip, skipToday, relax, open
}

/// Wraps UNUserNotificationCenter.
///
/// Permission state is never cached as "the truth": it is re-read from the system every
/// time the app becomes active, after every request and before showing the settings, so
/// granting permission in System Settings is picked up immediately.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum Status: Equatable {
        case unknown, notDetermined, denied, authorized, alertsOff, unavailable
    }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var lastError: String?

    var onAction: ((ReminderAction) -> Void)?

    private static let categoryID = "NECK_REMINDER"
    private static let requestID = "neck-reminder"

    /// UNUserNotificationCenter crashes when the process is not a bundled, signed app
    /// (e.g. `swift run`). Only touch it when we really are an app bundle.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
            ? UNUserNotificationCenter.current() : nil
    }

    var canDeliver: Bool { status == .authorized || status == .unknown }

    /// Must be called before the app finishes launching so action responses that launched
    /// the app are delivered.
    func configure() {
        guard let center else { status = .unavailable; return }
        center.delegate = self
        registerCategories()
    }

    func registerCategories() {
        guard let center else { return }
        let actions = [
            UNNotificationAction(identifier: ReminderAction.relax.rawValue, title: tr("放松颈椎", "Relax my neck"), options: [.foreground]),
            UNNotificationAction(identifier: ReminderAction.snooze5.rawValue, title: tr("5 分钟后提醒", "Remind in 5 min"), options: []),
            UNNotificationAction(identifier: ReminderAction.snooze10.rawValue, title: tr("10 分钟后提醒", "Remind in 10 min"), options: []),
            UNNotificationAction(identifier: ReminderAction.skip.rawValue, title: tr("本次忽略", "Skip this time"), options: []),
            UNNotificationAction(identifier: ReminderAction.skipToday.rawValue, title: tr("今日忽略", "Skip for today"), options: []),
        ]
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: actions, intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func refreshStatus() {
        guard let center else { status = .unavailable; return }
        center.getNotificationSettings { settings in
            let auth = settings.authorizationStatus
            let alerts = settings.alertSetting
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch auth {
                    case .notDetermined: self.status = .notDetermined
                    case .denied: self.status = .denied
                    case .authorized, .provisional:
                        self.status = alerts == .disabled ? .alertsOff : .authorized
                    @unknown default: self.status = .authorized
                    }
                }
            }
        }
    }

    func requestAuthorization() {
        guard let center else { status = .unavailable; return }
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            let message = error?.localizedDescription
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.lastError = message
                    self.refreshStatus()
                }
            }
        }
    }

    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    func deliver(title: String, body: String, sound: Bool) {
        guard let center else { return }
        registerCategories() // keep action titles in the current language
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.categoryID
        if sound { content.sound = .default }
        // Same identifier: a new reminder replaces the previous one instead of piling up.
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)
        center.add(request) { error in
            guard let error else { return }
            let message = error.localizedDescription
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.lastError = message }
            }
        }
    }

    func clearDelivered() {
        center?.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show the banner even while our own window is in front.
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.actionIdentifier
        let action: ReminderAction?
        if id == UNNotificationDefaultActionIdentifier {
            action = .open
        } else {
            action = ReminderAction(rawValue: id)
        }
        completionHandler()
        guard let action else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onAction?(action) }
        }
    }
}
