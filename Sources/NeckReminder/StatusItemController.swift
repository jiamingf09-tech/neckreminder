import AppKit
import NeckReminderCore

/// Menu bar icon with an optional "minutes until the next reminder" label.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let controller: ReminderController
    private let prefs: Preferences

    var onOpenMain: (() -> Void)?
    var onOpenGuide: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(controller: ReminderController, prefs: Preferences) {
        self.controller = controller
        self.prefs = prefs
        super.init()
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            item.menu = menu
            if let button = item.button {
                let image = NSImage(systemSymbolName: "figure.mind.and.body", accessibilityDescription: "NeckReminder")
                image?.isTemplate = true
                button.image = image
                button.imagePosition = .imageLeading
            }
            self.item = item
            refresh()
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func refresh() {
        guard let button = item?.button else { return }
        var title = ""
        if prefs.menuBarCountdown {
            if controller.isRelaxing {
                title = ""
            } else if controller.suppression != nil {
                title = " –"
            } else {
                let minutes = Int((controller.remaining / 60).rounded(.up))
                title = " \(minutes)\(tr("分", "m"))"
            }
        }
        if button.title != title { button.title = title }
        button.appearsDisabled = controller.suppression != nil || controller.state == .away
        button.toolTip = "NeckReminder — " + tr("已连续使用 \(formatMinutes(controller.continuousUse))",
                                                "\(formatMinutes(controller.continuousUse)) of continuous use")
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: tr("已连续使用 \(formatMinutes(controller.continuousUse))",
                                          "In use for \(formatMinutes(controller.continuousUse))"),
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let detail: String
        if let text = controller.suppressionText {
            detail = text
        } else {
            detail = tr("\(formatMinutes(controller.remaining))后提醒 · \(controller.stateTitle)",
                        "Next reminder in \(formatMinutes(controller.remaining)) · \(controller.stateTitle)")
        }
        let detailItem = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        menu.addItem(detailItem)
        menu.addItem(.separator())

        menu.addItem(makeItem(tr("立即放松颈椎…", "Relax my neck now…"), #selector(openGuide)))
        menu.addItem(makeItem(tr("我刚休息过（重新计时）", "I just took a break (reset)"), #selector(resetTimer)))
        menu.addItem(.separator())

        if controller.suppression != nil && prefs.enabled {
            menu.addItem(makeItem(tr("恢复提醒", "Resume reminders"), #selector(resume)))
        }
        let pauseItem = NSMenuItem(title: tr("暂停提醒", "Pause reminders"), action: nil, keyEquivalent: "")
        let pauseMenu = NSMenu()
        pauseMenu.autoenablesItems = false
        let options: [(String, Double)] = [
            (tr("30 分钟", "30 minutes"), 30 * 60),
            (tr("1 小时", "1 hour"), 3600),
            (tr("2 小时", "2 hours"), 7200),
            (tr("直到明天", "Until tomorrow"), -1),
            (tr("直到手动恢复", "Until I resume"), -2),
        ]
        for (title, seconds) in options {
            let item = makeItem(title, #selector(pause(_:)))
            item.representedObject = seconds
            pauseMenu.addItem(item)
        }
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)

        // "I'm reading / in a meeting": don't treat stillness as leaving for a while.
        let holdItem = NSMenuItem(title: tr("我在阅读 / 开会", "I'm reading / in a meeting"), action: nil, keyEquivalent: "")
        let holdMenu = NSMenu()
        holdMenu.autoenablesItems = false
        if let until = prefs.presenceHoldUntil, until > Date() {
            let f = DateFormatter()
            f.timeStyle = .short
            let info = NSMenuItem(title: tr("进行中，至 \(f.string(from: until))", "On until \(f.string(from: until))"), action: nil, keyEquivalent: "")
            info.isEnabled = false
            holdMenu.addItem(info)
            holdMenu.addItem(makeItem(tr("结束", "End now"), #selector(endHold)))
            holdMenu.addItem(.separator())
        }
        for minutes in [30, 60, 120] {
            let item = makeItem(minutes < 60 ? tr("\(minutes) 分钟内不判定离开", "Don't count me away for \(minutes) min")
                                             : tr("\(minutes / 60) 小时内不判定离开", "Don't count me away for \(minutes / 60) h"),
                                #selector(hold(_:)))
            item.representedObject = minutes
            holdMenu.addItem(item)
        }
        holdItem.submenu = holdMenu
        menu.addItem(holdItem)

        let enabledItem = makeItem(tr("启用提醒", "Reminders enabled"), #selector(toggleEnabled))
        enabledItem.state = prefs.enabled ? .on : .off
        menu.addItem(enabledItem)
        menu.addItem(.separator())

        menu.addItem(makeItem(tr("打开 NeckReminder", "Open NeckReminder"), #selector(openMain)))
        let settings = makeItem(tr("设置…", "Settings…"), #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = makeItem(tr("退出", "Quit"), #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openGuide() { onOpenGuide?() }
    @objc private func openMain() { onOpenMain?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func resetTimer() { controller.startBreak(); refresh() }
    @objc private func resume() { controller.resume(); refresh() }
    @objc private func toggleEnabled() { prefs.enabled.toggle(); refresh() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func hold(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        controller.holdPresence(minutes: minutes)
        refresh()
    }

    @objc private func endHold() {
        controller.cancelPresenceHold()
        refresh()
    }

    @objc private func pause(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        if seconds == -1 {
            controller.pauseUntilTomorrow()
        } else if seconds == -2 {
            controller.pauseIndefinitely()
        } else {
            controller.pause(for: seconds)
        }
        refresh()
    }
}
