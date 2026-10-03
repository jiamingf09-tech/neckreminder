import AppKit
import SwiftUI
import ServiceManagement
import NeckReminderCore

struct SettingsView: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var controller: ReminderController
    @EnvironmentObject var notifications: NotificationManager

    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?

    var body: some View {
        Form {
            remindersSection
            styleSection
            detectionSection
            DiagnosticsSection()
            appearanceSection
            systemSection
            relaxSection
        }
        .formStyle(.grouped)
        .onAppear {
            notifications.refreshStatus()
            refreshLoginItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItem()
        }
    }

    // MARK: Sections

    private var remindersSection: some View {
        Section {
            Toggle(tr("启用提醒", "Enable reminders"), isOn: $prefs.enabled)
            Picker(tr("连续使用多久后提醒", "Remind after continuous use of"), selection: $prefs.intervalMinutes) {
                ForEach([15, 20, 25, 30, 40, 45, 50, 60, 75, 90, 120], id: \.self) { m in
                    Text(formatMinutes(TimeInterval(m * 60))).tag(m)
                }
            }
            Picker(tr("没有处理时，再次提醒间隔", "If ignored, remind again after"), selection: $prefs.repeatMinutes) {
                ForEach([5, 10, 15, 20, 30], id: \.self) { m in
                    Text(formatMinutes(TimeInterval(m * 60))).tag(m)
                }
            }
        } header: {
            Text(tr("提醒", "Reminders"))
        }
    }

    private var styleSection: some View {
        Section {
            Toggle(tr("系统通知", "System notification"), isOn: $prefs.useNotification)
            if prefs.useNotification {
                HStack {
                    Text(tr("通知权限：", "Permission: ") + notifications.status.label)
                        .foregroundColor(notifications.status == .authorized ? .secondary : .orange)
                    Spacer()
                    switch notifications.status {
                    case .notDetermined:
                        Button(tr("请求权限", "Request")) { notifications.requestAuthorization() }
                    case .denied, .alertsOff, .authorized:
                        Button(tr("系统设置…", "System Settings…")) { notifications.openSystemSettings() }
                    default:
                        EmptyView()
                    }
                    Button {
                        notifications.refreshStatus()
                    } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(tr("重新检查", "Check again"))
                }
                if let error = notifications.lastError {
                    Text(error).font(.caption).foregroundColor(.red)
                }
                Toggle(tr("提示音", "Sound"), isOn: $prefs.notificationSound)
            }

            Picker(tr("全屏半透明提醒", "Full-screen overlay"), selection: $prefs.overlayMode) {
                ForEach(OverlayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if prefs.overlayMode != .off {
                HStack {
                    Text(tr("背景不透明度", "Backdrop opacity"))
                    Slider(value: $prefs.overlayOpacity, in: 0.15...0.8)
                    Text("\(Int(prefs.overlayOpacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Picker(tr("自动隐藏", "Hide automatically after"), selection: $prefs.overlaySeconds) {
                    Text(tr("15 秒", "15 s")).tag(15)
                    Text(tr("30 秒", "30 s")).tag(30)
                    Text(tr("1 分钟", "1 min")).tag(60)
                    Text(tr("2 分钟", "2 min")).tag(120)
                    Text(tr("直到我选择", "Until I choose")).tag(0)
                }
            }
            HStack {
                Button(tr("预览提醒", "Preview reminder")) { controller.fire(preview: true) }
                Spacer()
            }
        } header: {
            Text(tr("提醒方式", "How to remind"))
        } footer: {
            Text(tr("全屏提醒是半透明、点击穿透的：鼠标和键盘照常操作当前应用，只有按钮区域可以点击，也不会抢走输入焦点。若通知被关闭且全屏提醒也关闭，会自动改用全屏提醒，保证提醒不丢失。",
                    "The overlay is translucent and click-through: your mouse and keyboard keep working in the app underneath, only the buttons are clickable, and focus is never stolen. If notifications are unavailable and the overlay is off, the overlay is used anyway so no reminder is lost."))
        }
    }

    private var detectionSection: some View {
        Section {
            Picker(tr("多久没有操作视为离开", "Consider me away after no input for"), selection: $prefs.readingGraceMinutes) {
                ForEach([1.0, 2.0, 3.0, 4.0, 5.0, 7.0, 10.0], id: \.self) { m in
                    Text(formatMinutes(m * 60)).tag(m)
                }
            }
            Toggle(tr("播放视频或视频会议时延长判断", "Allow longer stillness while video or a call is playing"), isOn: $prefs.mediaExtension)
            if prefs.mediaExtension {
                Picker(tr("播放视频时多久没有操作视为离开", "…then away after no input for"), selection: $prefs.mediaGraceMinutes) {
                    ForEach([10, 15, 20, 30, 45, 60], id: \.self) { m in
                        Text(formatMinutes(TimeInterval(m * 60))).tag(m)
                    }
                }
            }
            Picker(tr("离开多久算一次休息（重新计时）", "Away this long counts as a break (timer restarts)"), selection: $prefs.breakResetMinutes) {
                ForEach([2, 3, 5, 8, 10, 15], id: \.self) { m in
                    Text(formatMinutes(TimeInterval(m * 60))).tag(m)
                }
            }
        } header: {
            Text(tr("智能判断", "Presence detection"))
        } footer: {
            Text(tr("""
            判断规则：只有真实的键盘、鼠标、触控板输入才算“在用电脑”，程序在跑、视频在放本身都不算。短暂没有操作（阅读、思考）的时间会先暂记，等你再次操作时才确认；一直没有操作就视为离开并扣除这段时间。锁屏、屏保、显示器休眠、电脑睡眠会立即视为离开。离开时间达到“休息”阈值就重新计时，短暂离开只暂停计时。从离开状态回来时，单次轻微的鼠标移动（比如碰到桌子）不会被当作回来。
            """, """
            Only real keyboard, mouse and trackpad input counts as using the computer — a running build or a playing video doesn't. Short stillness (reading, thinking) is held tentatively and confirmed when you touch the input again; if you never do, you're treated as away and that time is removed. Locking the screen, screen saver, display sleep and system sleep mean away immediately. Being away for the break threshold restarts the timer; shorter absences only pause it. A single small mouse nudge (bumping the desk) doesn't count as coming back.
            """))
        }
    }

    private var appearanceSection: some View {
        Section {
            Toggle(tr("在菜单栏显示", "Show in menu bar"), isOn: $prefs.showInMenuBar)
            if prefs.showInMenuBar {
                Toggle(tr("菜单栏显示倒计时", "Show countdown in menu bar"), isOn: $prefs.menuBarCountdown)
            }
            Toggle(tr("在 Dock 中显示", "Show in Dock"), isOn: $prefs.showInDock)
            Toggle(tr("启动时打开主窗口（开机自启时不打开）", "Open this window on launch (not at login)"), isOn: $prefs.showWindowOnLaunch)
            Picker(tr("语言", "Language"), selection: $prefs.language) {
                Text(tr("跟随系统", "System")).tag(AppLanguage.system)
                Text("简体中文").tag(AppLanguage.zh)
                Text("English").tag(AppLanguage.en)
            }
            if !prefs.showInMenuBar && !prefs.showInDock {
                Text(tr("菜单栏和 Dock 图标都已隐藏。需要时再次打开 NeckReminder.app 即可回到这个窗口（不会重复启动）。",
                        "Both the menu bar and Dock icons are hidden. Open NeckReminder.app again to get back here — it won't start a second copy."))
                    .font(.callout)
                    .foregroundColor(.orange)
            }
        } header: {
            Text(tr("外观", "Appearance"))
        }
    }

    private var systemSection: some View {
        Section {
            Toggle(tr("登录时自动启动", "Launch at login"), isOn: Binding(
                get: { loginEnabled },
                set: { newValue in
                    do {
                        try LoginItem.setEnabled(newValue)
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                    }
                    refreshLoginItem()
                }))
            if loginNeedsApproval {
                HStack {
                    Text(tr("需要在“系统设置 › 通用 › 登录项”中允许。", "Needs approval in System Settings › General › Login Items."))
                        .foregroundColor(.orange)
                    Spacer()
                    Button(tr("打开", "Open")) { LoginItem.openSystemSettings() }
                }
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundColor(.red)
            }
        } header: {
            Text(tr("系统", "System"))
        } footer: {
            Text(tr("NeckReminder 只需要“通知”这一项权限。不需要辅助功能、输入监控、屏幕录制、摄像头或麦克风权限，也不联网。",
                    "NeckReminder only asks for notification permission. No Accessibility, Input Monitoring, Screen Recording, camera or microphone access, and no network."))
        }
    }

    private var relaxSection: some View {
        Section {
            Picker(tr("默认放松时长", "Default session length"), selection: $prefs.defaultRoutineMinutes) {
                ForEach(ExerciseLibrary.routines) { r in
                    Text("\(r.minutes) \(tr("分钟", "min")) · \(r.title.text)").tag(r.minutes)
                }
            }
            Toggle(tr("切换动作时播放提示音", "Chime between exercises"), isOn: $prefs.stepChime)
            Toggle(tr("语音播报动作（适合闭眼跟练）", "Speak each exercise (eyes-closed friendly)"), isOn: $prefs.voiceGuidance)
        } header: {
            Text(tr("放松指南", "Relax guide"))
        }
    }

    private func refreshLoginItem() {
        loginEnabled = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
    }
}

/// Live view of the signals the detector uses — makes the "why" transparent.
struct DiagnosticsSection: View {
    @EnvironmentObject var controller: ReminderController

    var body: some View {
        Section {
            if let snap = controller.snapshot {
                row(tr("当前判断", "Current state"), controller.stateTitle)
                row(tr("距上次任意输入", "Since last input"), seconds(snap.sample.idleSeconds))
                row(tr("距上次按键 / 点击 / 滚动", "Since last key / click / scroll"), seconds(snap.sample.strongIdleSeconds))
                row(tr("屏幕已锁定", "Screen locked"), yesNo(snap.screenLocked))
                row(tr("显示器休眠", "Display asleep"), yesNo(snap.displayAsleep))
                row(tr("屏幕保护程序", "Screen saver"), yesNo(snap.screenSaver))
                row(tr("保持屏幕常亮的应用（视频 / 会议）", "Apps keeping the display on (video / calls)"),
                    snap.mediaApps.isEmpty ? tr("无", "None") : snap.mediaApps.joined(separator: ", "))
                row(tr("连续使用（含暂记）", "Continuous use (incl. tentative)"), formatMinutes(controller.continuousUse))
            } else {
                Text(tr("等待第一次采样…", "Waiting for the first sample…")).foregroundColor(.secondary)
            }
        } header: {
            Text(tr("实时检测状态", "Live detection"))
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary).monospacedDigit()
        }
    }

    private func seconds(_ s: TimeInterval) -> String {
        if s > 86_400 * 30 { return "—" }
        if s < 60 { return tr("\(Int(s)) 秒", "\(Int(s)) s") }
        return formatMinutes(s)
    }

    private func yesNo(_ b: Bool) -> String { b ? tr("是", "Yes") : tr("否", "No") }
}
