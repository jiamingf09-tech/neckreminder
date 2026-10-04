import AppKit
import SwiftUI
import NeckReminderCore

/// Native blur that samples what is *behind* the window, so a small panel stays legible
/// on any background without painting a solid block.
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

@MainActor
final class QuestionModel: ObservableObject {
    @Published var minutes = 0
    /// Describes what was going on, e.g. "Chrome 在播放视频（前台：PowerPoint）".
    @Published var detail: String?
    @Published var appName: String?
    @Published var secondsLeft = 20
    @Published var hovering = false
    @Published var scale = 1.0
}

/// Two small corner panels:
/// * the question "刚才 N 分钟没有操作 · App — 使用电脑 / 离开了" shown right when the user
///   comes back from an ambiguous silence;
/// * a faint, click-through "还在看吗？" hint shown while unsure — any mouse movement answers it.
/// Neither takes keyboard focus.
@MainActor
final class FeedbackPanelController: NSObject {
    private var questionPanel: OverlayPanel?
    private var probePanel: OverlayPanel?
    private let question = QuestionModel()
    private var questionTimer: Timer?
    private var episodeID: UUID?
    private var probeShownAt: Date?

    var onAnswer: ((UUID, PresenceLabel) -> Void)?
    var onNeverAskApp: ((UUID) -> Void)?
    var onUnanswered: ((UUID) -> Void)?

    var isQuestionVisible: Bool { questionPanel != nil }
    var isProbeVisible: Bool { probePanel != nil }

    // MARK: Question

    func ask(episode: GapEpisode, scale: Double) {
        dismissQuestion(answered: true)
        episodeID = episode.id
        question.minutes = max(1, Int((episode.gap.duration / 60).rounded()))
        question.detail = episode.context.summary
        question.appName = episode.context.appName
        question.secondsLeft = 20
        question.hovering = false
        question.scale = scale

        let view = QuestionView(model: question,
                                answer: { [weak self] label in self?.answer(label) },
                                neverAsk: { [weak self] in self?.neverAsk() },
                                close: { [weak self] in self?.dismissQuestion(answered: false) })
        let host = FirstMouseHostingView(rootView: view)
        let size = host.fittingSize
        guard let screen = OverlayController.activeScreen() else { return }
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - size.width - 16, y: visible.minY + 16, width: size.width, height: size.height)
        let panel = OverlayPanel(frame: frame, clickThrough: false)
        panel.level = .statusBar
        panel.contentView = host
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        questionPanel = panel

        let timer = Timer(timeInterval: 1, target: self, selector: #selector(questionTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        questionTimer = timer
    }

    @objc private func questionTick() {
        guard !question.hovering else { return }
        question.secondsLeft -= 1
        if question.secondsLeft <= 0 { dismissQuestion(answered: false) }
    }

    private func answer(_ label: PresenceLabel) {
        guard let id = episodeID else { return }
        dismissQuestion(answered: true)
        onAnswer?(id, label)
    }

    private func neverAsk() {
        guard let id = episodeID else { return }
        dismissQuestion(answered: true)
        onNeverAskApp?(id)
    }

    func dismissQuestion(answered: Bool) {
        questionTimer?.invalidate()
        questionTimer = nil
        if !answered, let id = episodeID { onUnanswered?(id) }
        episodeID = nil
        fadeOut(questionPanel)
        questionPanel = nil
    }

    // MARK: Probe

    func showProbe(scale: Double) {
        guard probePanel == nil, let screen = OverlayController.activeScreen() else { return }
        let host = NSHostingView(rootView: ProbeView(scale: scale))
        let size = host.fittingSize
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - size.width - 16, y: visible.minY + 16, width: size.width, height: size.height)
        let panel = OverlayPanel(frame: frame, clickThrough: true)
        panel.level = .statusBar
        panel.contentView = host
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 1.2; panel.animator().alphaValue = 0.9 }
        probePanel = panel
        probeShownAt = Date()
    }

    /// Seconds the probe has been visible, if it is.
    var probeAge: TimeInterval? { probeShownAt.map { Date().timeIntervalSince($0) } }

    func hideProbe() {
        fadeOut(probePanel)
        probePanel = nil
        probeShownAt = nil
    }

    private func fadeOut(_ panel: NSPanel?) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
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

    private var s: CGFloat { CGFloat(model.scale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "clock.badge.questionmark")
                    .foregroundColor(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("刚才 \(model.minutes) 分钟没有操作", "No input for the last \(model.minutes) min"))
                        .font(.system(size: 14 * s, weight: .semibold))
                    if let detail = model.detail {
                        Text(detail)
                            .font(.system(size: 11 * s))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10 * s, weight: .bold))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            Text(tr("这段时间你在：", "During that time you were:"))
                .font(.system(size: 12 * s))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button { answer(.present) } label: {
                    Label(tr("使用电脑", "Using the computer"), systemImage: "desktopcomputer")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuestionButtonStyle(prominent: true))
                Button { answer(.away) } label: {
                    Label(tr("离开了", "Away"), systemImage: "figure.walk")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuestionButtonStyle(prominent: false))
            }
            HStack {
                if let app = model.appName {
                    Button(tr("「\(app)」别再问", "Don't ask for \(app)"), action: neverAsk)
                        .buttonStyle(.borderless)
                        .font(.system(size: 11 * s))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(model.hovering ? "" : "\(model.secondsLeft)s")
                    .font(.system(size: 11 * s).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: 330 * s)
        .background(VisualEffectBlur(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .onHover { model.hovering = $0 }
        .padding(1)
    }
}

struct QuestionButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(prominent ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

struct ProbeView: View {
    var scale: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
            Text(tr("还在看吗？动一下鼠标就好", "Still there? Just move the mouse"))
        }
        .font(.system(size: 13 * CGFloat(scale), weight: .medium))
        .foregroundColor(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(VisualEffectBlur(material: .popover))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .padding(1)
        .allowsHitTesting(false)
    }
}
