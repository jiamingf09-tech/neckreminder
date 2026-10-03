import AppKit
import SwiftUI
import NeckReminderCore

/// Borderless, non-activating panel that floats above everything (including full-screen apps)
/// and never takes keyboard focus from the app the user is working in.
final class OverlayPanel: NSPanel {
    init(frame: NSRect, clickThrough: Bool) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        setFrame(frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = clickThrough
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        isFloatingPanel = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reacts to the first click even though its window is never key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct OverlayButton: Identifiable, Equatable {
    let id: String
    let title: String
    var symbol: String? = nil
}

/// What a full-screen overlay says and offers.
struct OverlayContent {
    var symbol = "figure.mind.and.body"
    var title: String
    var subtitle: String
    var primary: OverlayButton
    var secondary: [OverlayButton]
    /// Small line under the buttons; receives the seconds left before auto-hide (0 = none).
    var footnote: (Int) -> String?
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var symbol = "figure.mind.and.body"
    @Published var title = ""
    @Published var subtitle = ""
    @Published var opacity = 0.45
    @Published var celebrating = false
    @Published var secondsLeft = 0
    @Published var primary = OverlayButton(id: "", title: "")
    @Published var secondary: [OverlayButton] = []
    var footnote: (Int) -> String? = { _ in nil }
}

/// The optional full-screen reminder.
///
/// It is made of two windows per reminder:
/// * a click-through backdrop (semi-transparent, big text) — mouse and keyboard go straight
///   through to whatever is underneath, so typing and clicking keep working;
/// * a small button panel that accepts clicks but never becomes key, so pressing a button
///   doesn't steal keyboard focus either.
@MainActor
final class OverlayController: NSObject {
    private var backdrops: [OverlayPanel] = []
    private var actionsPanel: OverlayPanel?
    private let model = OverlayModel()
    private var countdown: Timer?
    private var onAction: ((String) -> Void)?
    private var onTimeout: (() -> Void)?

    var isVisible: Bool { !backdrops.isEmpty }

    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    func show(mode: OverlayMode, content: OverlayContent, opacity: Double,
              autoHideSeconds: Int, onAction: @escaping (String) -> Void, onTimeout: (() -> Void)? = nil) {
        dismiss(animated: false)
        guard mode != .off, let active = Self.activeScreen() else { return }
        self.onAction = onAction
        self.onTimeout = onTimeout

        model.symbol = content.symbol
        model.title = content.title
        model.subtitle = content.subtitle
        model.primary = content.primary
        model.secondary = content.secondary
        model.footnote = content.footnote
        model.opacity = opacity
        model.celebrating = false
        model.secondsLeft = autoHideSeconds

        let screens = mode == .allScreens ? NSScreen.screens : [active]
        for screen in screens {
            let panel = makeBackdrop(on: screen)
            backdrops.append(panel)
        }

        let actions = OverlayActionsView(model: model) { [weak self] id in
            self?.onAction?(id)
        }
        let host = FirstMouseHostingView(rootView: actions.environment(\.colorScheme, .dark))
        let size = host.fittingSize
        let frame = NSRect(x: active.frame.midX - size.width / 2,
                           y: active.frame.minY + active.frame.height * 0.24,
                           width: size.width, height: size.height)
        let panel = OverlayPanel(frame: frame, clickThrough: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.contentView = host
        actionsPanel = panel

        for window in backdrops + [panel] {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            for window in backdrops + [panel] { window.animator().alphaValue = 1 }
        }

        if autoHideSeconds > 0 {
            let timer = Timer(timeInterval: 1, target: self, selector: #selector(countdownTick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            countdown = timer
        }
    }

    @objc private func countdownTick() {
        model.secondsLeft -= 1
        if model.secondsLeft <= 0 {
            let timeout = onTimeout
            dismiss(animated: true)
            timeout?()
        }
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        countdown?.invalidate()
        countdown = nil
        onAction = nil
        onTimeout = nil
        let windows = backdrops + [actionsPanel].compactMap { $0 }
        backdrops = []
        actionsPanel = nil
        guard !windows.isEmpty else { completion?(); return }
        guard animated else {
            windows.forEach { $0.orderOut(nil) }
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            for window in windows { window.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated {
                windows.forEach { $0.orderOut(nil) }
                completion?()
            }
        })
    }

    /// "Relax my neck" was chosen: confetti on the active display, then `completion`.
    func celebrate(completion: @escaping () -> Void) {
        countdown?.invalidate()
        countdown = nil
        onAction = nil
        onTimeout = nil
        actionsPanel?.orderOut(nil)
        actionsPanel = nil

        guard let screen = Self.activeScreen() else { completion(); return }
        if backdrops.isEmpty {
            model.opacity = 0.2
            let panel = makeBackdrop(on: screen)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            backdrops = [panel]
        }
        model.celebrating = true
        model.secondsLeft = 0
        model.title = tr("好样的！", "Nice one!")
        model.subtitle = tr("跟着指南，花几分钟放松一下颈椎吧", "Let's spend a few minutes loosening up your neck")

        let target = backdrops.first { $0.frame == screen.frame } ?? backdrops[0]
        if let container = target.contentView {
            let confetti = ConfettiView(frame: container.bounds)
            confetti.autoresizingMask = [.width, .height]
            container.addSubview(confetti)
            confetti.burst()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            MainActor.assumeIsolated {
                self?.dismiss(animated: true, completion: completion)
            }
        }
    }

    private func makeBackdrop(on screen: NSScreen) -> OverlayPanel {
        let panel = OverlayPanel(frame: screen.frame, clickThrough: true)
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: OverlayBackdropView(model: model))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container
        return panel
    }
}

// MARK: - Views

struct OverlayBackdropView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack {
            Color.black.opacity(model.opacity)
            RadialGradient(colors: [Color(red: 0.2, green: 0.75, blue: 0.7).opacity(0.22), .clear],
                           center: .center, startRadius: 20, endRadius: 760)
            VStack(spacing: 20) {
                Image(systemName: model.celebrating ? "party.popper.fill" : model.symbol)
                    .font(.system(size: 88, weight: .light))
                Text(model.title)
                    .font(.system(size: 68, weight: .bold, design: .rounded))
                Text(model.subtitle)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .opacity(0.92)
            }
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.55), radius: 14, y: 2)
            .padding(80)
            .offset(y: -120)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct OverlayActionsView: View {
    @ObservedObject var model: OverlayModel
    let onAction: (String) -> Void

    var body: some View {
        // No panel behind the buttons: each control carries its own small blur and the text a
        // soft shadow, so it stays readable on any wallpaper without covering a block of screen.
        VStack(spacing: 16) {
            Button { onAction(model.primary.id) } label: {
                Label(model.primary.title, systemImage: model.primary.symbol ?? "figure.mind.and.body")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .frame(minWidth: 300)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 28)
            }
            .buttonStyle(OverlayPrimaryButtonStyle())

            HStack(spacing: 10) {
                ForEach(model.secondary) { button in
                    Button { onAction(button.id) } label: {
                        Text(button.title)
                            .font(.system(size: 15, weight: .medium))
                            .padding(.vertical, 9)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(OverlaySecondaryButtonStyle())
                }
            }

            if let note = model.footnote(model.secondsLeft) {
                Text(note)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.8), radius: 3)
            }
        }
        .padding(16)
        .fixedSize()
    }
}

struct OverlayPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(
                Capsule().fill(LinearGradient(colors: [Color(red: 0.18, green: 0.78, blue: 0.62),
                                                       Color(red: 0.1, green: 0.6, blue: 0.85)],
                                              startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
    }
}

struct OverlaySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.7), radius: 2)
            .background(
                VisualEffectBlur(material: .fullScreenUI)
                    .overlay(Color.white.opacity(configuration.isPressed ? 0.18 : 0))
                    .clipShape(Capsule())
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35)))
            .contentShape(Capsule())
    }
}

// MARK: - Confetti

/// Two "party cannons" firing from the bottom corners. Purely decorative and click-through.
final class ConfettiView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func burst() {
        guard let layer else { return }
        let w = bounds.width, h = bounds.height
        let colors: [NSColor] = [.systemPink, .systemYellow, .systemTeal, .systemOrange,
                                 .systemPurple, .systemGreen, .systemBlue, .systemRed]
        let cannons: [(CGPoint, CGFloat)] = [
            (CGPoint(x: w * 0.04, y: 0), .pi * 0.35),
            (CGPoint(x: w * 0.96, y: 0), .pi * 0.65),
        ]
        var emitters: [CAEmitterLayer] = []
        for (position, angle) in cannons {
            let emitter = CAEmitterLayer()
            emitter.frame = bounds
            emitter.emitterPosition = position
            emitter.emitterShape = .point
            emitter.beginTime = CACurrentMediaTime()
            emitter.emitterCells = colors.flatMap { color in
                [Self.cell(color: color, round: false, height: h, angle: angle),
                 Self.cell(color: color, round: true, height: h, angle: angle)]
            }
            layer.addSublayer(emitter)
            emitters.append(emitter)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            emitters.forEach { $0.birthRate = 0 }
        }
    }

    private static func cell(color: NSColor, round: Bool, height: CGFloat, angle: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image(color: color, round: round)
        cell.birthRate = 22
        cell.lifetime = 5
        cell.velocity = height * 1.35
        cell.velocityRange = height * 0.35
        cell.emissionLongitude = angle
        cell.emissionRange = .pi / 9
        cell.yAcceleration = -height * 0.9
        cell.spin = 3.5
        cell.spinRange = 6
        cell.scale = 1
        cell.scaleRange = 0.4
        cell.alphaSpeed = -0.12
        return cell
    }

    private static func image(color: NSColor, round: Bool) -> CGImage? {
        let width = round ? 9 : 14, height = round ? 9 : 8
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(color.usingColorSpace(.deviceRGB)?.cgColor ?? color.cgColor)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if round { ctx.fillEllipse(in: rect) } else { ctx.fill(rect) }
        return ctx.makeImage()
    }
}
