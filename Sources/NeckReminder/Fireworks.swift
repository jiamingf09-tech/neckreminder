import AppKit
import SwiftUI

/// Fireworks drawn with Core Animation particle emitters: rockets rise from the bottom
/// edge with a short trail and burst into sparks at the top of their flight.
/// Purely decorative and click-through.
final class FireworksView: NSView {
    private var emitter: CAEmitterLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard let emitter else { return }
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: 0)
        emitter.emitterSize = CGSize(width: bounds.width * 0.7, height: 1)
    }

    /// Launch rockets for `duration` seconds.
    func launch(duration: TimeInterval = 3.5) {
        guard let layer, bounds.width > 10, bounds.height > 10 else { return }
        emitter?.removeFromSuperlayer()

        let h = bounds.height
        let e = CAEmitterLayer()
        e.frame = bounds
        e.emitterPosition = CGPoint(x: bounds.midX, y: 0)
        e.emitterSize = CGSize(width: bounds.width * 0.7, height: 1)
        e.emitterShape = .line
        e.renderMode = .additive
        e.beginTime = CACurrentMediaTime()

        let rocket = CAEmitterCell()
        rocket.birthRate = Float(max(2.5, min(7, bounds.width / 220)))
        rocket.lifetime = 1.15
        rocket.velocity = h * 0.95
        rocket.velocityRange = h * 0.18
        rocket.emissionLongitude = .pi / 2 // straight up (layer coordinates are y-up)
        rocket.emissionRange = .pi / 9
        rocket.yAcceleration = -h * 0.42
        rocket.contents = Self.dot(diameter: 6)
        rocket.scale = 0.7
        rocket.color = NSColor.white.cgColor

        let trail = CAEmitterCell()
        trail.birthRate = 45
        trail.lifetime = 0.45
        trail.velocity = 8
        trail.emissionRange = .pi * 2
        trail.alphaSpeed = -2
        trail.scale = 0.35
        trail.scaleSpeed = -0.6
        trail.contents = Self.dot(diameter: 6)
        trail.color = NSColor(calibratedRed: 1, green: 0.85, blue: 0.55, alpha: 1).cgColor

        // Sparks: emitted only at the very end of each rocket's life → a burst.
        var sparks: [CAEmitterCell] = []
        for color in Self.colors {
            let spark = CAEmitterCell()
            spark.beginTime = CFTimeInterval(rocket.lifetime - 0.06)
            spark.duration = 0.06
            spark.birthRate = 2_400 / Float(Self.colors.count)
            spark.lifetime = 2.2
            spark.lifetimeRange = 0.6
            spark.velocity = h * 0.2
            spark.velocityRange = h * 0.08
            spark.emissionRange = .pi * 2
            spark.yAcceleration = -h * 0.09
            spark.alphaSpeed = -0.45
            spark.scale = 0.55
            spark.scaleRange = 0.2
            spark.scaleSpeed = -0.12
            spark.spin = 2
            spark.spinRange = 3
            spark.contents = Self.dot(diameter: 7)
            spark.color = color.cgColor
            sparks.append(spark)
        }
        rocket.emitterCells = [trail] + sparks
        e.emitterCells = [rocket]
        layer.addSublayer(e)
        emitter = e

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            e.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 3.5) { [weak e] in
            e?.removeFromSuperlayer()
        }
    }

    private static let colors: [NSColor] = [
        NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.42, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.25, alpha: 1),
        NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.35, green: 0.7, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.78, green: 0.5, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.85, alpha: 1),
    ]

    private static func dot(diameter: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: diameter, height: diameter, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(diameter) / 2, options: [])
        }
        return ctx.makeImage()
    }
}

/// SwiftUI wrapper: fireworks (and confetti) fire whenever `trigger` changes.
struct FireworksLayer: NSViewRepresentable {
    var trigger: Int
    var confetti = true
    var duration: TimeInterval = 3.5

    final class Container: NSView {
        let fireworks = FireworksView(frame: .zero)
        let confettiView = ConfettiView(frame: .zero)
        var lastTrigger = Int.min

        override init(frame: NSRect) {
            super.init(frame: frame)
            for v in [fireworks, confettiView] as [NSView] {
                v.autoresizingMask = [.width, .height]
                v.frame = bounds
                addSubview(v)
            }
        }

        required init?(coder: NSCoder) { fatalError("not used") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Container { Container(frame: .zero) }

    func updateNSView(_ view: Container, context: Context) {
        guard trigger != view.lastTrigger else { return }
        let first = view.lastTrigger == Int.min
        view.lastTrigger = trigger
        guard !first || trigger > 0 else { return }
        // Wait a beat so the view has its final size.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MainActor.assumeIsolated {
                view.fireworks.launch(duration: duration)
                if confetti { view.confettiView.burst() }
            }
        }
    }
}
