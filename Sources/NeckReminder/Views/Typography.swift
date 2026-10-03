import SwiftUI

/// App-wide text size multiplier (Settings › Appearance, or A−/A+ in the relax player).
private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    var textScale: Double {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * CGFloat(scale), weight: weight, design: design))
    }
}

extension View {
    /// A system font whose size follows the app's text-size setting.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

enum TextScale {
    static let options: [Double] = [0.9, 1.0, 1.15, 1.3, 1.5, 1.75]
    static let range: ClosedRange<Double> = 0.9...1.75

    static func label(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    static func step(_ v: Double, up: Bool) -> Double {
        if up { return options.first { $0 > v + 0.001 } ?? options.last! }
        return options.last { $0 < v - 0.001 } ?? options.first!
    }
}
