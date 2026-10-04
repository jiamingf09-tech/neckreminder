import AppKit
import SwiftUI
import NeckReminderCore

/// Native blur that samples what is *behind* the window, so a small panel stays legible
/// on any background without painting a solid block. The system materials also adapt
/// their tint and the text's vibrancy to light / dark content behind them.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Frosted, translucent card: blur of what's behind + a faint sheen and hairline border.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                ZStack {
                    VisualEffectBlur(material: .popover)
                    LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
            )
    }
}

@MainActor
final class QuestionModel: ObservableObject {
    @Published var minutes = 0
    /// Describes what was going on, e.g. "Chrome 在播放视频（前台：PowerPoint）".
    @Published var detail: String?
    @Published var appName: String?
    @Published var secondsLeft = 20
    @Published var hovering = false
    @Published var scale = 1.0
    /// Set right after a click: what was recorded (drives the check-mark state).
    @Published var confirmation: (title: String, detail: String)?
    @Published var leaving = false

    var isDone: Bool { confirmation != nil }
}

/// Two small corner panels:
/// * the question "刚才 N 分钟没有操作 — 使用电脑 / 离开了" shown right when the user
///   comes back from an ambiguous silence;
/// * a faint, click-through "还在看吗？" hint shown while unsure — any mouse movement answers it.
/// Neither takes keyboard focus.
@MainActor
final class FeedbackPanelController: NSObject {
    private var questionPanel: OverlayPanel?
    private var probePanel: OverlayPanel?
    private var question = QuestionModel()
    private var questionTimer: Timer?
    private var episodeID: UUID?
    private var probeShownAt: Date?

    var onAnswer: ((UUID, PresenceLabel) -> Void)?
    var onNeverAskApp: ((UUID) -> Void)?
    var onUnanswered: ((UUID) -> Void)?

    var isQuestionVisible: Bool { questionPanel != nil }
    var isProbeVisible: Bool { probePanel != nil }

    /// Timing: clicks take effect at once; the confirmation stays long enough to be seen.
    private static let confirmationHold: TimeInterval = 1.5
    private static let leaveDuration: TimeInterval = 0.5

    // MARK: Question

    func ask(episode: GapEpisode, scale: Double) {
        removeQuestionImmediately()
        let model = QuestionModel()
        model.minutes = max(1, Int((episode.gap.duration / 60).rounded()))
        model.detail = episode.context.summary
        model.appName = episode.context.appName
        model.scale = scale
        question = model
        episodeID = episode.id

        let view = QuestionView(model: model,
                                answer: { [weak self] label in self?.answer(label) },
                                neverAsk: { [weak self] in self?.neverAsk() },
                                close: { [weak self] in self?.dismissQuestion(answered: false) })
        let host = FirstMouseHostingView(rootView: view)
        let size = host.fittingSize
        guard let screen = OverlayController.activeScreen() else { return }
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - size.width - 12, y: visible.minY + 12, width: size.width, height: size.height)
        let panel = OverlayPanel(frame: frame, clickThrough: false)
        panel.level = .statusBar
        panel.hasShadow = true
        panel.contentView = host
        panel.orderFrontRegardless()
        questionPanel = panel

        let timer = Timer(timeInterval: 1, target: self, selector: #selector(questionTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        questionTimer = timer
    }

    @objc private func questionTick() {
        guard !question.hovering, !question.isDone else { return }
        question.secondsLeft -= 1
        if question.secondsLeft <= 0 { dismissQuestion(answered: false) }
    }

    private func answer(_ label: PresenceLabel) {
        guard let id = episodeID, !question.isDone else { return }
        // Record immediately; the animation is only feedback.
        onAnswer?(id, label)
        confirmAndLeave(title: tr("已记录", "Recorded"),
                        detail: label == .present ? tr("这段时间在使用电脑", "You were using the computer")
                                                  : tr("这段时间离开了电脑", "You were away"))
    }

    private func neverAsk() {
        guard let id = episodeID, !question.isDone else { return }
        onNeverAskApp?(id)
        confirmAndLeave(title: tr("好的", "Got it"),
                        detail: tr("以后不再询问「\(question.appName ?? "")」", "Won't ask about \(question.appName ?? "this app") again"))
    }

    private func confirmAndLeave(title: String, detail: String) {
        questionTimer?.invalidate()
        questionTimer = nil
        episodeID = nil
        let model = question
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            model.confirmation = (title, detail)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmationHold) { [weak self] in
            MainActor.assumeIsolated { self?.leave(model) }
        }
    }

    /// Close without an answer (×, timeout, or a new question replacing this one).
    func dismissQuestion(answered: Bool) {
        questionTimer?.invalidate()
        questionTimer = nil
        if !answered, let id = episodeID { onUnanswered?(id) }
        episodeID = nil
        leave(question)
    }

    private func leave(_ model: QuestionModel) {
        guard model === question, let panel = questionPanel else { return }
        questionPanel = nil
        withAnimation(.easeIn(duration: Self.leaveDuration)) { model.leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.leaveDuration + 0.05) {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func removeQuestionImmediately() {
        questionTimer?.invalidate()
        questionTimer = nil
        questionPanel?.orderOut(nil)
        questionPanel = nil
        episodeID = nil
    }

    // MARK: Probe

    func showProbe(scale: Double) {
        guard probePanel == nil, let screen = OverlayController.activeScreen() else { return }
        let host = NSHostingView(rootView: ProbeView(scale: scale))
        let size = host.fittingSize
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - size.width - 12, y: visible.minY + 12, width: size.width, height: size.height)
        let panel = OverlayPanel(frame: frame, clickThrough: true)
        panel.level = .statusBar
        panel.hasShadow = true
        panel.contentView = host
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 1.2; panel.animator().alphaValue = 0.95 }
        probePanel = panel
        probeShownAt = Date()
    }

    /// Seconds the probe has been visible, if it is.
    var probeAge: TimeInterval? { probeShownAt.map { Date().timeIntervalSince($0) } }

    func hideProbe() {
        guard let panel = probePanel else { return }
        probePanel = nil
        probeShownAt = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 },
                                             completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

// MARK: - Views

struct QuestionView: View {
    @ObservedObject var model: QuestionModel
    let answer: (PresenceLabel) -> Void
    let neverAsk: () -> Void
    let close: () -> Void
    @State private var appeared = false

    private var s: CGFloat { CGFloat(model.scale) }

    var body: some View {
        GlassCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12 * s) {
                header
                    // The headline moves up a little when the answer is recorded.
                    .offset(y: model.isDone ? -4 * s : 0)
                content
                    .opacity(model.isDone ? 0 : 1)
                    .overlay {
                        if let c = model.confirmation {
                            ConfirmationView(title: c.title, detail: c.detail, scale: s)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
            }
            .padding(18 * s)
            .frame(width: 390 * s, alignment: .leading)
        }
        .padding(14) // room for the window shadow
        .scaleEffect(model.leaving ? 0.94 : (appeared ? 1 : 0.96), anchor: .bottomTrailing)
        .offset(y: model.leaving ? 10 : (appeared ? 0 : 12))
        .opacity(model.leaving ? 0 : (appeared ? 1 : 0))
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { appeared = true }
        }
        .onHover { model.hovering = $0 }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10 * s) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 20 * s))
                .foregroundStyle(Palette.gradient)
            VStack(alignment: .leading, spacing: 3 * s) {
                Text(tr("刚才 \(model.minutes) 分钟没有操作", "No input for the last \(model.minutes) min"))
                    .font(.system(size: 16 * s, weight: .semibold))
                if let detail = model.detail {
                    Text(detail)
                        .font(.system(size: 12.5 * s))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !model.isDone {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11 * s, weight: .bold))
                        .frame(width: 22 * s, height: 22 * s)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help(tr("不回答", "Skip"))
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            Text(tr("这段时间你在：", "During that time you were:"))
                .font(.system(size: 13 * s))
                .foregroundColor(.secondary)
            HStack(spacing: 10 * s) {
                answerButton(.present, tr("使用电脑", "Using the computer"), "desktopcomputer", prominent: true)
                answerButton(.away, tr("离开了", "Away"), "figure.walk", prominent: false)
            }
            HStack {
                if let app = model.appName {
                    Button(tr("「\(app)」别再问", "Don't ask for \(app)"), action: neverAsk)
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5 * s))
                        .foregroundColor(.secondary)
                        .underline()
                }
                Spacer()
                Text(model.hovering ? tr("已暂停", "paused") : "\(model.secondsLeft)s")
                    .font(.system(size: 11.5 * s).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .disabled(model.isDone)
    }

    private func answerButton(_ label: PresenceLabel, _ title: String, _ symbol: String, prominent: Bool) -> some View {
        Button { answer(label) } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 14 * s, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9 * s)
        }
        .buttonStyle(QuestionButtonStyle(prominent: prominent))
    }
}

/// Green check + what was recorded.
private struct ConfirmationView: View {
    let title: String
    let detail: String
    let scale: CGFloat
    @State private var drawn = false

    var body: some View {
        VStack(spacing: 8 * scale) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.82, blue: 0.45),
                                                  Color(red: 0.12, green: 0.66, blue: 0.36)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.green.opacity(0.35), radius: 8, y: 2)
                Image(systemName: "checkmark")
                    .font(.system(size: 20 * scale, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(drawn ? 1 : 0.3)
                    .opacity(drawn ? 1 : 0)
            }
            .frame(width: 44 * scale, height: 44 * scale)
            VStack(spacing: 2 * scale) {
                Text(title).font(.system(size: 14 * scale, weight: .semibold))
                Text(detail).font(.system(size: 12 * scale)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.6).delay(0.12)) { drawn = true }
        }
    }
}

struct QuestionButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(prominent ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.09)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(prominent ? 0 : 0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct ProbeView: View {
    var scale: Double

    var body: some View {
        GlassCard(cornerRadius: 22) {
            HStack(spacing: 10) {
                Image(systemName: "eye")
                    .foregroundStyle(Palette.gradient)
                Text(tr("还在看吗？动一下鼠标就好", "Still there? Just move the mouse"))
            }
            .font(.system(size: 14 * CGFloat(scale), weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }
        .padding(14)
        .allowsHitTesting(false)
    }
}
