import AppKit
import SwiftUI
import ServiceManagement
import NeckReminderCore

struct SettingsView: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var controller: ReminderController
    @EnvironmentObject var notifications: NotificationManager
    @EnvironmentObject var learning: LearningStore

    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?

    var body: some View {
        Form {
            remindersSection
            styleSection
            detectionSection
            learningSection
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
                    Text(error).scaledFont(10.5).foregroundColor(.red)
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
            Picker(tr("离开多久就重新计算连续时长", "Away this long restarts the continuous count"), selection: $prefs.breakResetMinutes) {
                ForEach([1, 2, 3, 5, 10], id: \.self) { m in
                    Text(formatMinutes(TimeInterval(m * 60))).tag(m)
                }
            }
        } header: {
            Text(tr("智能判断", "Presence detection"))
        } footer: {
            Text(tr("""
            判断规则：只有真实的键盘、鼠标、触控板输入才算“在用电脑”，程序在跑、视频在放本身都不算。短暂没有操作（阅读、思考）的时间会先暂记，等你再次操作时才确认；一直没有操作就视为离开并扣除这段时间。锁屏、屏保、显示器休眠、电脑睡眠会立即视为离开。只要确认你离开了电脑（默认 1 分钟以上，锁屏也算），连续时长就会清零重新计算。从离开状态回来时，单次轻微的鼠标移动（比如碰到桌子）不会被当作回来。
            """, """
            Only real keyboard, mouse and trackpad input counts as using the computer — a running build or a playing video doesn't. Short stillness (reading, thinking) is held tentatively and confirmed when you touch the input again; if you never do, you're treated as away and that time is removed. Locking the screen, screen saver, display sleep and system sleep mean away immediately. Once you've actually left (1 minute by default, locking the screen counts), the continuous count restarts. A single small mouse nudge (bumping the desk) doesn't count as coming back.
            """))
        }
    }

    private var learningSection: some View {
        Section {
            Toggle(tr("回到电脑时，偶尔问一句刚才是否在使用", "When I come back, occasionally ask whether I was using the computer"),
                   isOn: $prefs.askOnReturn)
            if prefs.askOnReturn {
                Picker(tr("每天最多询问", "At most per day"), selection: $prefs.maxQuestionsPerDay) {
                    ForEach([2, 3, 5, 8, 12], id: \.self) { n in Text(tr("\(n) 次", "\(n) times")).tag(n) }
                }
            }
            Toggle(tr("拿不准时，在角落淡出「还在看吗？」（动一下鼠标即可）",
                      "When unsure, fade in \u{201C}Still there?\u{201D} in the corner (just move the mouse)"),
                   isOn: $prefs.probeEnabled)
            HStack {
                let a = PresenceModel.accuracy(learning.episodes)
                Text(a.total == 0
                     ? tr("还没有回答记录", "No answers yet")
                     : tr("已回答 \(a.total) 次 · 回答前判断正确率 \(Int(Double(a.correct) / Double(a.total) * 100))%",
                          "\(a.total) answers · right \(Int(Double(a.correct) / Double(a.total) * 100))% before answering"))
                    .foregroundColor(.secondary)
                Spacer()
            }
        } header: {
            Text(tr("学习与反馈", "Learning & feedback"))
        } footer: {
            Text(tr("问题只在判断拿不准时出现，出现在右下角，不抢键盘焦点，20 秒后自动消失。你的回答会立即修正刚才的计时，并在本机训练一个小模型：每个应用、是否在放视频 / 画中画 / 音乐、是否在通话都会分别学习。演示或全屏时不会弹出，可以之后在「回顾」里确认。",
                    "Questions appear only when detection is unsure — bottom-right, never stealing keyboard focus, gone after 20 s. Answers fix the timer immediately and train a small on-device model per app and per situation (video, picture in picture, music, calls). Nothing pops up while you present or are full screen; confirm those later in Review."))
        }
    }

    private var appearanceSection: some View {
        Section {
            Toggle(tr("在菜单栏显示", "Show in menu bar"), isOn: $prefs.showInMenuBar)
            if prefs.showInMenuBar {
                Toggle(tr("菜单栏显示倒计时", "Show countdown in menu bar"), isOn: $prefs.menuBarCountdown)
            }
            Toggle(tr("在 Dock 中显示", "Show in Dock"), isOn: $prefs.showInDock)
            Picker(tr("文字大小", "Text size"), selection: $prefs.textScale) {
                ForEach(TextScale.options, id: \.self) { v in
                    Text(v == 1.0 ? tr("标准 (100%)", "Default (100%)") : TextScale.label(v)).tag(v)
                }
            }
            Toggle(tr("启动时打开主窗口（开机自启时不打开）", "Open this window on launch (not at login)"), isOn: $prefs.showWindowOnLaunch)
            Picker(tr("语言", "Language"), selection: $prefs.language) {
                Text(tr("跟随系统", "System")).tag(AppLanguage.system)
                Text("简体中文").tag(AppLanguage.zh)
                Text("English").tag(AppLanguage.en)
            }
            if !prefs.showInMenuBar && !prefs.showInDock {
                Text(tr("菜单栏和 Dock 图标都已隐藏。需要时再次打开 NeckReminder.app 即可回到这个窗口（不会重复启动）。",
                        "Both the menu bar and Dock icons are hidden. Open NeckReminder.app again to get back here — it won't start a second copy."))
                    .scaledFont(12)
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
                Text(loginError).scaledFont(10.5).foregroundColor(.red)
            }
        } header: {
            Text(tr("系统", "System"))
        } footer: {
            Text(tr("NeckReminder 只需要“通知”权限。不需要辅助功能、输入监控、屏幕录制、摄像头或麦克风权限。只在你打开示范视频时访问 YouTube，其余不联网。",
                    "NeckReminder only asks for notification permission. No Accessibility, Input Monitoring, Screen Recording, camera or microphone access. The network is used only when you open a demo video."))
        }
    }

    private var relaxSection: some View {
        Section {
            Picker(tr("默认放松时长", "Default session length"), selection: $prefs.defaultRoutineMinutes) {
                ForEach(ExerciseLibrary.routines) { r in
                    Text("\(r.minutes) \(tr("分钟", "min")) · \(r.title.text)").tag(r.minutes)
                }
            }
            Picker(tr("每个动作前的准备时间", "Get-ready time before each exercise"), selection: $prefs.prepSeconds) {
                ForEach([5, 8, 10, 15], id: \.self) { n in Text(tr("\(n) 秒", "\(n) s")).tag(n) }
            }
            Toggle(tr("推荐组合（每次不同，优先最近没做过的动作）", "Varied mixes (favouring exercises you haven't done lately)"),
                   isOn: $prefs.variedRoutines)
            Toggle(tr("切换动作时播放提示音", "Chime between exercises"), isOn: $prefs.stepChime)
            Toggle(tr("语音播报动作（默认关闭，跟练时也可随时切换）", "Speak each exercise (off by default; can be toggled during a session)"), isOn: $prefs.voiceGuidance)
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
                row(tr("前台应用", "Front app"), (snap.frontmostName ?? "—") + (snap.frontmostFullscreen ? tr("（全屏）", " (full screen)") : ""))
                row(tr("画中画窗口", "Picture in picture"), snap.pipApps.isEmpty ? tr("无", "None") : snap.pipApps.joined(separator: ", "))
                row(tr("正在出声的应用", "Apps playing sound"),
                    snap.audibleApps.isEmpty ? tr("无", "None") : snap.audibleApps.joined(separator: ", "))
                row(tr("麦克风 / 摄像头使用中", "Microphone / camera in use"),
                    "\(yesNo(snap.devices.micInUse)) / \(yesNo(snap.devices.cameraInUse))")
                row(tr("通话判断", "Call"), callLabel(snap.call))
                row(tr("当前离开阈值（学习后）", "Away threshold (learned)"), formatMinutes(controller.currentGrace))
                if let p = controller.presenceProbability {
                    row(tr("仍在使用的可能性", "Probability still here"), "\(Int(p * 100))%")
                }
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

    private func callLabel(_ c: CallKind) -> String {
        switch c {
        case .none: return tr("无", "None")
        case .voice: return tr("语音通话（不需要看屏幕）", "Voice call (no screen needed)")
        case .meeting: return tr("会议（关闭摄像头）", "Meeting (camera off)")
        case .video: return tr("视频通话", "Video call")
        }
    }
}
