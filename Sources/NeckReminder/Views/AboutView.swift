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
                        Text("NeckReminder").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(tr("版本 \(version)", "Version \(version)")).foregroundColor(.secondary)
                        Text(tr("提醒你在长时间连续使用电脑后，放松一下颈椎。", "Reminds you to rest your neck after long stretches at the computer."))
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tr("隐私", "Privacy"), systemImage: "lock.shield").font(.headline)
                        bullet(tr("不使用摄像头、麦克风或任何传感器。", "No camera, microphone or other sensors."))
                        bullet(tr("只读取“距离上次输入过了多少秒”，从不读取你按了什么键。", "Reads only *how long ago* the last input happened — never what you typed."))
                        bullet(tr("不需要辅助功能 / 输入监控 / 屏幕录制权限，只需要通知权限。", "No Accessibility / Input Monitoring / Screen Recording permission; notifications only."))
                        bullet(tr("所有数据只保存在本机，不联网。", "Everything stays on this Mac; no network access."))
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tr("如何判断你在连续使用电脑", "How continuous use is detected"), systemImage: "brain.head.profile").font(.headline)
                        bullet(tr("活跃：最近有真实的键盘 / 鼠标 / 触控板输入（软件模拟的输入不算）。", "Active: recent real keyboard / mouse / trackpad input (software-generated events don't count)."))
                        bullet(tr("阅读 / 观看：短时间没有输入，先暂记这段时间，等你再次操作时确认。", "Reading / watching: a short pause is counted tentatively and confirmed when you interact again."))
                        bullet(tr("离开：超过阈值没有输入（播放视频、视频会议时阈值更长），或锁屏、屏保、显示器 / 系统睡眠。暂记的时间会被扣除。", "Away: no input past the threshold (longer while video or a call keeps the display on), or the screen is locked / asleep. Tentative time is removed."))
                        bullet(tr("休息：离开达到设定时长（默认 5 分钟）即重新计时；更短的离开只暂停计时。", "Break: being away for the set time (5 min by default) restarts the timer; shorter absences only pause it."))
                        bullet(tr("防误判：离开后单次轻微的鼠标移动不会被当作回来；按键、点击或持续操作才算。", "No false returns: one small mouse nudge while away is ignored; a key, click or continued movement is needed."))
                        bullet(tr("在你安静阅读时到点，提醒会等你下一次操作再出现，而不是对着空座位弹出。", "If a reminder comes due while you're quietly reading, it waits for your next input instead of popping up at an empty chair."))
                    }
                }

                Text(ExerciseLibrary.safetyNote.text)
                    .font(.callout)
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
