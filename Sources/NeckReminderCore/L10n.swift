import Foundation

/// UI language. The app ships Simplified Chinese and English strings inline
/// (no resource bundles, which keeps the hand-assembled .app bundle simple).
public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, zh, en
    public var id: String { rawValue }
}

public enum L10n {
    public static var language: AppLanguage = .system

    public static var isChinese: Bool {
        switch language {
        case .zh: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
        }
    }
}

/// Pick the Chinese or English variant according to the current language.
public func tr(_ zh: String, _ en: String) -> String {
    L10n.isChinese ? zh : en
}

/// A bilingual piece of text used by static content (exercises, routines, tips).
public struct LText: Hashable {
    public let zh: String
    public let en: String

    public init(_ zh: String, _ en: String) {
        self.zh = zh
        self.en = en
    }

    public var text: String { tr(zh, en) }
}

/// Human friendly duration, e.g. "1 小时 5 分钟" / "1h 5m".
public func formatMinutes(_ seconds: TimeInterval) -> String {
    let total = max(0, Int((seconds / 60).rounded(.down)))
    let h = total / 60
    let m = total % 60
    if h > 0 {
        return m > 0 ? tr("\(h) 小时 \(m) 分钟", "\(h)h \(m)m") : tr("\(h) 小时", "\(h)h")
    }
    return tr("\(m) 分钟", "\(m) min")
}

/// "mm:ss" clock string for countdowns.
public func formatClock(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.up)))
    return String(format: "%d:%02d", s / 60, s % 60)
}
