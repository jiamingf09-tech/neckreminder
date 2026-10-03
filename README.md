# NeckReminder

一个轻量的 macOS 菜单栏应用：**准确判断你是否在连续使用电脑**，到点后通过系统通知和（可选的）半透明全屏提示提醒你放松颈椎，并内置 2 / 5 / 10 / 15 / 30 分钟的颈椎舒缓跟练指南。

- 原生 Swift（AppKit + SwiftUI），无第三方依赖，单一 **Universal** 二进制（Apple Silicon + Intel），支持 macOS 13 Ventura 及以上。
- **只需要“通知”一项权限**。不需要辅助功能、输入监控、屏幕录制、摄像头或麦克风，也不联网。

## 功能

| | |
|---|---|
| 智能判断连续使用 | 只看真实的键盘 / 鼠标 / 触控板输入和锁屏状态，详见下文 |
| 提醒间隔 | 15–120 分钟可选（默认 30 分钟），未处理时每 N 分钟再次提醒 |
| 系统通知 | 带操作按钮：放松颈椎 / 5 分钟后 / 10 分钟后 / 本次忽略 / 今日忽略 |
| 全屏提醒（可选） | 关闭 / 当前活跃显示器 / 所有显示器；**半透明、点击穿透、不抢焦点**，大号文字；按钮：5 分钟后提醒、10 分钟后提醒、本次忽略、今日忽略，以及更大的“放松颈椎” |
| 放松颈椎 | 礼炮动画 → 打开应用内舒缓指南，按可用时间选 2 / 5 / 10 / 15 / 30 分钟方案，逐步计时、提示音、可选语音播报 |
| 时间安排 | 按星期几跳过；多个免打扰时段（支持跨夜，如 22:00–08:00）；临时暂停 30 分钟 / 1 小时 / 2 小时 / 到明天 |
| 菜单栏 | 图标 + 可选倒计时；快速放松、重新计时、暂停 |
| Dock | 可选隐藏 Dock 图标（默认隐藏） |
| 单实例 | 重复打开不会启动第二份，只会把已运行实例的主界面调出来 |
| 统计 | 今日使用时长、最长连续使用、提醒次数、完成放松次数、自然休息次数、最近 7 天柱状图 |
| 开机自启 | `SMAppService`，状态始终从系统读取 |
| 语言 | 简体中文 / English / 跟随系统 |

## 如何判断“正在连续使用电脑”

这是整个应用最关键的部分，目标是**少误报**：人走了不要算，人在看东西不要漏。

**信号（全部无需权限）**

1. `CGEventSource.secondsSinceLastEventType(.hidSystemState, …)`：距离上次**硬件**输入的秒数。只告诉“多久之前”，不告诉“按了什么”；使用 `.hidSystemState` 会忽略软件模拟的事件（远程工具、“鼠标抖动器”）。分别读取“任意输入”和“按键 / 点击 / 滚动”两种。
2. 锁屏、屏幕保护、显示器休眠、系统睡眠、快速切换用户：系统通知 + `CGSessionCopyCurrentDictionary`。
3. 显示器常亮电源断言（与 `pmset -g assertions` 同源）：某个 GUI 应用（浏览器视频、播放器、视频会议）阻止显示器休眠时，说明大概率有人在看。`caffeinate`、Amphetamine 等“防休眠”工具会被排除。

**状态机**（每 5 秒采样一次，见 `Sources/NeckReminderCore/UsageTracker.swift`）

```
          有新输入                       超过阅读宽限(默认3分钟)无输入
 ┌────────┐  ─────►  ┌────────┐ 30秒无输入 ┌─────────────┐ ─────────────────► ┌────────┐
 │  离开   │          │  活跃   │ ────────► │ 阅读/观看中   │     锁屏/屏保/睡眠    │  离开   │
 └────────┘ ◄─────── └────────┘ ◄──────── └─────────────┘ ─────────────────► └────────┘
   需可信输入           时间直接确认    再次输入：暂记时间全部确认       暂记时间被扣除
```

- **程序在跑、视频在放 ≠ 在用电脑**：只有真实输入才是“在场”的证据，后台编译、下载、播放都不会让计时增长。
- **在看内容但没操作**：短时间无输入（默认 3 分钟内）视为阅读/思考，这段时间**先暂记**；你再次动鼠标键盘时确认计入，若一直不动则判定离开并**扣除**这段暂记时间（离开时刻按最后一次输入算）。
- **看视频 / 开视频会议**：有 GUI 应用保持屏幕常亮时，宽限延长到 20 分钟（可调或关闭）。
- **短暂离开 vs 真正休息**：离开不足“休息阈值”（默认 5 分钟）只暂停计时；达到阈值则视为休息，计时清零。锁屏、合盖睡眠直接视为离开。
- **防止误判回来**：离开状态下，一次轻微的鼠标移动（碰到桌子、猫踩触控板）不算回来；需要按键 / 点击 / 滚动，或连续两个采样周期都有移动。
- **不对空座位弹提醒**：到点时如果你正在安静阅读（无输入，且没有视频播放），提醒会等到你下一次操作时再出现。
- 设置页有“实时检测状态”面板，可以直接看到每个信号的当前值，方便理解和调参。

## 权限说明（避免“授权了却显示未授权”）

- 唯一需要的权限是通知。首次启动请求一次；之后每次应用回到前台、打开设置页都会**重新从系统读取**授权状态，而不是使用缓存，所以在“系统设置 › 通知”里打开后立即生效。
- 通知不可用（被拒绝 / 提醒样式为“无”）且全屏提醒关闭时，会自动改用全屏提醒，保证提醒不丢失。
- 刻意**没有**使用事件监听（`CGEventTap` / `NSEvent` 全局监听），因此不会触发“辅助功能 / 输入监控”授权——这类授权与代码签名绑定，ad-hoc 签名的应用每次更新后都会出现“已勾选但仍未授权”的问题。

## 构建

需要 macOS + Xcode 15 或更高版本。

```bash
swift test                     # 核心算法单元测试
scripts/build-app.sh           # 生成 dist/NeckReminder.app（universal，ad-hoc 签名）
scripts/make-dmg.sh            # 打包 dist/NeckReminder.dmg
open dist/NeckReminder.app
```

`VERSION`、`BUILD_NUMBER`、`CODESIGN_IDENTITY` 环境变量可覆盖版本号与签名身份。

### CI/CD

`.github/workflows/build.yml` 在 `macos-15` 上运行：单元测试 → 构建 **一个 universal 包**（`lipo` 校验同时包含 arm64 与 x86_64）→ 产出 `.dmg` 与 `.zip` 构件。推送 `v*` 标签（如 `v1.0.0`）会自动创建 GitHub Release。

可选：配置以下仓库 Secrets 即启用 Developer ID 签名与公证，否则为 ad-hoc 签名：

| Secret | 说明 |
|---|---|
| `MACOS_CERTIFICATE_P12` | Developer ID Application 证书 .p12 的 base64 |
| `MACOS_CERTIFICATE_PASSWORD` | .p12 密码 |
| `MACOS_SIGNING_IDENTITY` | 如 `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_APPLE_ID` / `NOTARY_PASSWORD` / `NOTARY_TEAM_ID` | 公证用 Apple ID、App 专用密码、Team ID |

未公证的构建首次打开时，请右键 → 打开，或执行 `xattr -dr com.apple.quarantine /Applications/NeckReminder.app`。

## 项目结构

```
Sources/NeckReminderCore/   纯逻辑，可单测：UsageTracker（判断算法）、ReminderPolicy、ScheduleRules、Exercises（指南内容）
Sources/NeckReminder/       应用：ActivityMonitor（信号采集）、ReminderController、OverlayController（全屏提醒 + 礼炮）、
                            NotificationManager、StatusItemController、RelaxSession（计时器）、Views/
Tests/                      算法与内容测试
scripts/                    构建 .app / 图标 / DMG
docs/neck-relief-guide.md   颈椎舒缓指南（文字版）
```

## 免责声明

指南仅用于日常保健，不能替代医疗建议。出现手臂放射痛、麻木无力、头晕恶心、外伤后颈痛或疼痛持续加重时，请停止练习并就医。
