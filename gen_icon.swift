import AppKit

// Renders Smiley.iconset (all macOS icon sizes): blue squircle, big 😀, 📷 at bottom-right.
// Usage: swift gen_icon.swift && iconutil -c icns Smiley.iconset -o AppIcon.icns

let iconsetPath = "Smiley.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let S = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Big Sur-style squircle: ~80% of canvas, centered, transparent margins
    let m = S * 0.098
    let path = NSBezierPath(roundedRect: CGRect(x: m, y: m, width: S - 2 * m, height: S - 2 * m),
                            xRadius: S * 0.18, yRadius: S * 0.18)
    NSGradient(starting: NSColor(calibratedRed: 0.31, green: 0.76, blue: 0.97, alpha: 1),
               ending: NSColor(calibratedRed: 0.12, green: 0.53, blue: 0.90, alpha: 1))!
        .draw(in: path, angle: 90)

    func drawEmoji(_ e: String, size: CGFloat, center: CGPoint) {
        let str = NSAttributedString(string: e, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let sz = str.size()
        str.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
    }
    drawEmoji("😀", size: S * 0.52, center: CGPoint(x: S * 0.50, y: S * 0.56))
    drawEmoji("📷", size: S * 0.30, center: CGPoint(x: S * 0.66, y: S * 0.30))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in entries {
    try! render(px).write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}
print("iconset written")
