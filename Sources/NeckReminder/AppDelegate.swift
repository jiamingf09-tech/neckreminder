import AppKit
import SwiftUI
import Combine
import NeckReminderCore

@main
enum NeckReminderMain {
    @MainActor
    static func main() {
        guard SingleInstance.acquire() else {
            // Another copy is already running: bring its window up and quit.
            SingleInstance.signalRunningInstance()
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs: Preferences
    private let stats: StatsStore
    private let notifications: NotificationManager
    private let controller: ReminderController
    private let session: RelaxSession
    private var mainWindow: MainWindowController!
    private var statusItem: StatusItemController!
    private var cancellables = Set<AnyCancellable>()
    private var activity: NSObjectProtocol?

    override init() {
        prefs = Preferences()
        stats = StatsStore()
        notifications = NotificationManager()
        controller = ReminderController(prefs: prefs, stats: stats, notifications: notifications)
        session = RelaxSession(prefs: prefs)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be set before launch completes so notification actions are delivered.
        notifications.configure()
        NSApp.setActivationPolicy(prefs.showInDock ? .regular : .accessory)
        NSApp.mainMenu = MainMenu.build(target: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchedAtLogin = Self.wasLaunchedAsLoginItem()

        mainWindow = MainWindowController { [unowned self] in
            AnyView(RootView(navigation: self.mainWindow.navigation)
                .environmentObject(self.prefs)
                .environmentObject(self.stats)
                .environmentObject(self.controller)
                .environmentObject(self.notifications)
                .environmentObject(self.session))
        }

        statusItem = StatusItemController(controller: controller, prefs: prefs)
        statusItem.onOpenMain = { [weak self] in self?.mainWindow.show(.overview) }
        statusItem.onOpenGuide = { [weak self] in self?.mainWindow.show(.relax) }
        statusItem.onOpenSettings = { [weak self] in self?.mainWindow.show(.settings) }
        statusItem.setVisible(prefs.showInMenuBar)

        controller.onOpenGuide = { [weak self] in self?.mainWindow.show(.relax) }
        controller.onOpenMain = { [weak self] in self?.mainWindow.show(.overview) }
        controller.onTick = { [weak self] in self?.statusItem.refresh() }

        session.onStarted = { [weak self] in self?.controller.relaxSessionStarted() }
        session.onEnded = { [weak self] completed, elapsed in
            self?.controller.relaxSessionEnded(completed: completed, elapsed: elapsed)
        }

        // React to appearance settings.
        prefs.$showInDock.dropFirst().removeDuplicates()
            .sink { [weak self] show in self?.applyDockVisibility(show) }
            .store(in: &cancellables)
        prefs.$showInMenuBar.dropFirst().removeDuplicates()
            .sink { [weak self] show in self?.statusItem.setVisible(show) }
            .store(in: &cancellables)
        prefs.$language.dropFirst().removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    NSApp.mainMenu = MainMenu.build(target: self)
                    self.notifications.registerCategories()
                    self.statusItem.refresh()
                }
            }
            .store(in: &cancellables)

        // Second launches ask us to show the window.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showFromOtherInstance),
            name: SingleInstance.showWindowNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)

        // Keep the 5 s sampling timer punctual (no App Nap) while still allowing idle sleep.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Measuring continuous computer use")

        // Permissions: only notifications, asked once, state re-read whenever we come forward.
        notifications.refreshStatus()
        if prefs.useNotification && !prefs.hasLaunchedBefore {
            notifications.requestAuthorization()
        }

        controller.start()

        let firstLaunch = !prefs.hasLaunchedBefore
        prefs.hasLaunchedBefore = true
        if firstLaunch || (prefs.showWindowOnLaunch && !launchedAtLogin) || (!prefs.showInMenuBar && !prefs.showInDock && !launchedAtLogin) {
            mainWindow.show(.overview)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock icon click or double-clicking the app while it's already running.
        mainWindow.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        stats.save()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    @objc private func showFromOtherInstance() {
        mainWindow.show()
    }

    @objc private func appBecameActive() {
        // The user may have just changed permissions in System Settings.
        notifications.refreshStatus()
    }

    private func applyDockVisibility(_ show: Bool) {
        let wasVisible = mainWindow.isVisible
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if wasVisible {
            // Switching policy can hide our windows; bring the window back.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.mainWindow.show() }
            }
        }
    }

    // MARK: Menu actions

    @objc func showMainWindow(_ sender: Any?) { mainWindow.show(.overview) }
    @objc func showSettings(_ sender: Any?) { mainWindow.show(.settings) }
    @objc func showAbout(_ sender: Any?) { mainWindow.show(.about) }
    @objc func showRelax(_ sender: Any?) { mainWindow.show(.relax) }

    /// `true` when macOS started us as a login item.
    private static func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        let keyAEPropData = AEKeyword(0x7072_6474)          // 'prdt'
        let keyAELaunchedAsLogInItem = OSType(0x6C67_6974)  // 'lgit'
        let kAEOpenApplication = AEEventID(0x6F61_7070)    // 'oapp'
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

enum MainMenu {
    @MainActor
    static func build(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("关于 NeckReminder", "About NeckReminder"), action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "").target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("设置…", "Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",").target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("隐藏 NeckReminder", "Hide NeckReminder"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: tr("隐藏其他", "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("退出 NeckReminder", "Quit NeckReminder"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: tr("编辑", "Edit"))
        editMenu.addItem(withTitle: tr("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: tr("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: tr("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: tr("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: tr("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: tr("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: tr("窗口", "Window"))
        windowMenu.addItem(withTitle: tr("放松指南", "Relax guide"), action: #selector(AppDelegate.showRelax(_:)), keyEquivalent: "r").target = target
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: tr("最小化", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: tr("关闭", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return main
    }
}
