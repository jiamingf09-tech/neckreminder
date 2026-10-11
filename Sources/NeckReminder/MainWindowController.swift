import AppKit
import SwiftUI
import NeckReminderCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, achievements, review, relax, library, schedule, settings, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return tr("概览", "Overview")
        case .achievements: return tr("成就", "Achievements")
        case .review: return tr("回顾", "Review")
        case .relax: return tr("放松指南", "Relax")
        case .library: return tr("动作库", "Exercises")
        case .schedule: return tr("时间安排", "Schedule")
        case .settings: return tr("设置", "Settings")
        case .about: return tr("关于", "About")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "speedometer"
        case .achievements: return "trophy"
        case .review: return "clock.arrow.circlepath"
        case .relax: return "figure.mind.and.body"
        case .library: return "list.bullet.rectangle"
        case .schedule: return "calendar"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class Navigation: ObservableObject {
    @Published var section: AppSection? = .overview
}

/// Owns the one and only main window. Closing it only hides it.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let navigation = Navigation()
    private let makeRoot: () -> AnyView

    init(makeRoot: @escaping () -> AnyView) {
        self.makeRoot = makeRoot
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show(_ section: AppSection? = nil) {
        if let section { navigation.section = section }
        let window = self.window ?? makeWindow()
        self.window = window
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: makeRoot())
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "NeckReminder"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 640))
        window.contentMinSize = NSSize(width: 760, height: 540)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MainWindow")
        return window
    }
}
