// Renders the app icon into an .iconset folder (no image assets in the repo).
// Usage: make-icon <output.iconset>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(px)
    let inset = s * 0.098
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.18, green: 0.80, blue: 0.66, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.86, alpha: 1),
    ])
    gradient?.draw(in: path, angle: -70)

    // Soft highlight at the top.
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: rect.minX - rect.width * 0.2, y: rect.midY,
                                width: rect.width * 1.4, height: rect.height * 0.9)).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.40, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "figure.mind.and.body", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        let white = NSImage(size: size, flipped: false) { r in
            symbol.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        white.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2 - s * 0.01,
                              width: size.width, height: size.height))
    }
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    guard let data = render(px) else { fatalError("could not render \(px)px") }
    try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
}
print("Wrote \(sizes.count) images to \(output)")
