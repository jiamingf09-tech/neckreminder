import Foundation
import NeckReminderCore

enum OverlayMode: String, CaseIterable, Identifiable {
    case off, activeScreen, allScreens
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return tr("关闭", "Off")
        case .activeScreen: return tr("当前活跃显示器", "Active display")
        case .allScreens: return tr("所有显示器", "All displays")
        }
    }
}

/// All user settings, persisted in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    // Reminders
    @Published var enabled: Bool { didSet { set(enabled, "enabled") } }
    @Published var intervalMinutes: Int { didSet { set(intervalMinutes, "intervalMinutes") } }
    @Published var repeatMinutes: Int { didSet { set(repeatMinutes, "repeatMinutes") } }
    @Published var useNotification: Bool { didSet { set(useNotification, "useNotification") } }
    @Published var notificationSound: Bool { didSet { set(notificationSound, "notificationSound") } }
    @Published var overlayMode: OverlayMode { didSet { set(overlayMode.rawValue, "overlayMode") } }
    @Published var overlayOpacity: Double { didSet { set(overlayOpacity, "overlayOpacity") } }
    /// Seconds before the overlay hides itself; 0 = stay until a button is pressed.
    @Published var overlaySeconds: Int { didSet { set(overlaySeconds, "overlaySeconds") } }

    // Detection
    @Published var readingGraceMinutes: Double { didSet { set(readingGraceMinutes, "readingGraceMinutes") } }
    @Published var mediaExtension: Bool { didSet { set(mediaExtension, "mediaExtension") } }
    @Published var mediaGraceMinutes: Int { didSet { set(mediaGraceMinutes, "mediaGraceMinutes") } }
    @Published var breakResetMinutes: Int { didSet { set(breakResetMinutes, "breakResetMinutes") } }

    // Appearance
    @Published var showInDock: Bool { didSet { set(showInDock, "showInDock") } }
    @Published var showInMenuBar: Bool { didSet { set(showInMenuBar, "showInMenuBar") } }
    @Published var menuBarCountdown: Bool { didSet { set(menuBarCountdown, "menuBarCountdown") } }
    @Published var showWindowOnLaunch: Bool { didSet { set(showWindowOnLaunch, "showWindowOnLaunch") } }
    @Published var language: AppLanguage {
        didSet { set(language.rawValue, "language"); L10n.language = language }
    }

    // Relax
    @Published var defaultRoutineMinutes: Int { didSet { set(defaultRoutineMinutes, "defaultRoutineMinutes") } }
    @Published var stepChime: Bool { didSet { set(stepChime, "stepChime") } }
    @Published var voiceGuidance: Bool { didSet { set(voiceGuidance, "voiceGuidance") } }
    /// Pause before every exercise to read what's next.
    @Published var prepSeconds: Int { didSet { set(prepSeconds, "prepSeconds") } }
    /// true: varied mixes; false: the fixed classic routines.
    @Published var variedRoutines: Bool { didSet { set(variedRoutines, "variedRoutines") } }

    // Schedule
    @Published var schedule: ScheduleRules { didSet { setCodable(schedule, "schedule") } }
    @Published var pausedUntil: Date? { didSet { set(pausedUntil, "pausedUntil") } }
    @Published var ignoredDay: String? { didSet { set(ignoredDay, "ignoredDay") } }

    // Learning & feedback
    /// Ask "were you using the computer?" when coming back from an ambiguous silence.
    @Published var askOnReturn: Bool { didSet { set(askOnReturn, "askOnReturn") } }
    @Published var maxQuestionsPerDay: Int { didSet { set(maxQuestionsPerDay, "maxQuestionsPerDay") } }
    /// Show the faint "still there?" hint when unsure.
    @Published var probeEnabled: Bool { didSet { set(probeEnabled, "probeEnabled") } }
    /// Apps for which no questions are asked.
    @Published var noAskApps: [String] { didSet { set(noAskApps, "noAskApps") } }
    /// "I'm reading / in a meeting": don't treat stillness as away until this time.
    @Published var presenceHoldUntil: Date? { didSet { set(presenceHoldUntil, "presenceHoldUntil") } }

    // Bluetooth headset
    @Published var bluetoothEnabled: Bool { didSet { set(bluetoothEnabled, "bluetoothEnabled") } }
    @Published var bluetoothAddress: String? { didSet { set(bluetoothAddress, "bluetoothAddress") } }

    // Text size (1.0 = system default)
    @Published var textScale: Double { didSet { set(textScale, "textScale") } }

    // Bookkeeping
    @Published var hasLaunchedBefore: Bool { didSet { set(hasLaunchedBefore, "hasLaunchedBefore") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func v<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: key) as? T ?? fallback }

        enabled = v("enabled", true)
        intervalMinutes = v("intervalMinutes", 30)
        repeatMinutes = v("repeatMinutes", 10)
        useNotification = v("useNotification", true)
        notificationSound = v("notificationSound", true)
        overlayMode = OverlayMode(rawValue: v("overlayMode", OverlayMode.activeScreen.rawValue)) ?? .activeScreen
        overlayOpacity = v("overlayOpacity", 0.45)
        overlaySeconds = v("overlaySeconds", 60)

        readingGraceMinutes = v("readingGraceMinutes", 3.0)
        mediaExtension = v("mediaExtension", true)
        mediaGraceMinutes = v("mediaGraceMinutes", 20)
        breakResetMinutes = v("breakResetMinutes", 5)

        showInDock = v("showInDock", false)
        showInMenuBar = v("showInMenuBar", true)
        menuBarCountdown = v("menuBarCountdown", true)
        showWindowOnLaunch = v("showWindowOnLaunch", true)
        language = AppLanguage(rawValue: v("language", AppLanguage.system.rawValue)) ?? .system

        defaultRoutineMinutes = v("defaultRoutineMinutes", 5)
        stepChime = v("stepChime", true)
        voiceGuidance = v("voiceGuidance", false)
        prepSeconds = v("prepSeconds", 8)
        variedRoutines = v("variedRoutines", true)

        if let data = defaults.data(forKey: "schedule"),
           let rules = try? JSONDecoder().decode(ScheduleRules.self, from: data) {
            schedule = rules
        } else {
            schedule = ScheduleRules()
        }
        pausedUntil = defaults.object(forKey: "pausedUntil") as? Date
        ignoredDay = defaults.string(forKey: "ignoredDay")
        askOnReturn = v("askOnReturn", true)
        maxQuestionsPerDay = v("maxQuestionsPerDay", 5)
        probeEnabled = v("probeEnabled", true)
        noAskApps = v("noAskApps", [String]())
        presenceHoldUntil = defaults.object(forKey: "presenceHoldUntil") as? Date
        bluetoothEnabled = v("bluetoothEnabled", false)
        bluetoothAddress = defaults.string(forKey: "bluetoothAddress")
        textScale = v("textScale", 1.0)
        hasLaunchedBefore = v("hasLaunchedBefore", false)

        L10n.language = language
    }

    var trackerConfig: TrackerConfig {
        var c = TrackerConfig()
        c.readingGrace = readingGraceMinutes * 60
        c.mediaGrace = mediaExtension ? Double(mediaGraceMinutes) * 60 : 0
        c.breakReset = Double(breakResetMinutes) * 60
        return c
    }

    private func set(_ value: Any?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private func setCodable<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
