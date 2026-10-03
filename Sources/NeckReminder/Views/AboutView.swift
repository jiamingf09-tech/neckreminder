import AppKit
import SwiftUI
import NeckReminderCore

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NeckReminder").scaledFont(26, weight: .bold, design: .rounded)
                        Text(tr("版本 \(version)", "Version \(version)")).foregroundColor(.secondary)
                        Text(tr("提醒你在长时间连续使用电脑后，放松一下颈椎。", "Reminds you to rest your neck after long stretches at the computer."))
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tr("隐私", "Privacy"), systemImage: "lock.shield").scaledFont(13, weight: .semibold)
                        bullet(tr("不使用摄像头、麦克风或任何传感器。", "No camera, microphone or other sensors."))
                        bullet(tr("只读取“距离上次输入过了多少秒”，从不读取你按了什么键。", "Reads only *how long ago* the last input happened — never what you typed."))
                        bullet(tr("不需要辅助功能 / 输入监控 / 屏幕录制权限；只需要通知权限（开启蓝牙耳机判断时另需蓝牙权限）。", "No Accessibility / Input Monitoring / Screen Recording permission; notifications only (plus Bluetooth if you use the headset option)."))
                        bullet(tr("麦克风、摄像头只读取“是否正被其他应用使用”的状态（菜单栏橙点 / 绿点背后的信息），从不录音录像。", "For the microphone and camera only the \u{201C}in use by another app\u{201D} flag is read (what drives the orange / green dots) — nothing is recorded."))
                        bullet(tr("学习数据只保存在本机；只在你打开示范视频时访问 YouTube。", "Learning data stays on this Mac; the network is only used when you open a demo video."))
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tr("如何判断你在连续使用电脑", "How continuous use is detected"), systemImage: "brain.head.profile").scaledFont(13, weight: .semibold)
                        bullet(tr("活跃：最近有真实的键盘 / 鼠标 / 触控板输入（软件模拟的输入不算）。", "Active: recent real keyboard / mouse / trackpad input (software-generated events don't count)."))
                        bullet(tr("阅读 / 观看：短时间没有输入，先暂记这段时间，等你再次操作时确认。", "Reading / watching: a short pause is counted tentatively and confirmed when you interact again."))
                        bullet(tr("离开：超过阈值没有输入（播放视频、视频会议时阈值更长），或锁屏、屏保、显示器 / 系统睡眠。暂记的时间会被扣除。", "Away: no input past the threshold (longer while video or a call keeps the display on), or the screen is locked / asleep. Tentative time is removed."))
                        bullet(tr("休息：离开达到设定时长（默认 5 分钟）即重新计时；更短的离开只暂停计时。", "Break: being away for the set time (5 min by default) restarts the timer; shorter absences only pause it."))
                        bullet(tr("防误判：离开后单次轻微的鼠标移动不会被当作回来；按键、点击或持续操作才算。", "No false returns: one small mouse nudge while away is ignored; a key, click or continued movement is needed."))
                        bullet(tr("在你安静阅读时到点，提醒会等你下一次操作再出现，而不是对着空座位弹出。", "If a reminder comes due while you're quietly reading, it waits for your next input instead of popping up at an empty chair."))
                        bullet(tr("会学习：前台应用、窗口 / 全屏 / 画中画视频、只有声音（音乐）、语音通话与视频会议都会分别学习“多久没操作才算离开”。回到电脑时偶尔问一句，你的回答马上修正计时并训练本机模型。", "It learns: how long stillness means \u{201C}away\u{201D} is learned separately per app and for windowed / full-screen / picture-in-picture video, audio only (music), voice calls and meetings. Occasional questions when you return fix the timer at once and train the on-device model."))
                        bullet(tr("可选：蓝牙耳机信号逐渐减弱后断开，直接判定为离开。", "Optional: a Bluetooth headset fading out and disconnecting counts as leaving."))
                    }
                }

                Text(ExerciseLibrary.safetyNote.text)
                    .scaledFont(12)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
