#!/usr/bin/env swift
// Renders the app icon and the menu bar template icon into the asset catalog.
// Usage: swift scripts/make-icons.swift DeepSeekNative/Resources/Assets.xcassets
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icons.swift <Assets.xcassets>\n".utf8))
    exit(1)
}
let assets = URL(fileURLWithPath: CommandLine.arguments[1])

/// Whale silhouette in a 100×100 unit space with y pointing down. Bounds ≈ x 14…98, y 21…77.
func whalePath() -> NSBezierPath {
    let p = NSBezierPath()
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
    p.move(to: pt(14, 60))
    p.curve(to: pt(42, 35), controlPoint1: pt(14, 44), controlPoint2: pt(26, 35))      // forehead
    p.curve(to: pt(75, 49), controlPoint1: pt(57, 35), controlPoint2: pt(67, 41))      // back
    p.curve(to: pt(80, 33), controlPoint1: pt(79, 45), controlPoint2: pt(81, 39))      // tail stock, left edge
    p.curve(to: pt(69, 20), controlPoint1: pt(75, 31), controlPoint2: pt(71, 26))      // left fluke, lower edge
    p.curve(to: pt(84, 28), controlPoint1: pt(76, 20), controlPoint2: pt(81, 23))      // left fluke, upper edge
    p.curve(to: pt(99, 20), controlPoint1: pt(87, 23), controlPoint2: pt(92, 20))      // right fluke, upper edge
    p.curve(to: pt(88, 33), controlPoint1: pt(97, 26), controlPoint2: pt(93, 31))      // right fluke, lower edge
    p.curve(to: pt(86, 50), controlPoint1: pt(87, 38), controlPoint2: pt(87, 45))      // tail stock, right edge
    p.curve(to: pt(50, 76), controlPoint1: pt(83, 64), controlPoint2: pt(71, 76))      // belly
    p.curve(to: pt(14, 60), controlPoint1: pt(28, 76), controlPoint2: pt(14, 70))      // chin
    p.close()
    // Eye, cut out of the body.
    p.appendOval(in: NSRect(x: 26, y: 50.5, width: 7, height: 7))
    p.windingRule = .evenOdd
    return p
}

/// Maps unit space onto `rect` (y-up), scaling the glyph so its width equals `rect.width`.
func placedWhale(in rect: NSRect) -> NSBezierPath {
    let glyphBounds = NSRect(x: 14, y: 20, width: 85, height: 57)
    let scale = rect.width / glyphBounds.width
    let transform = NSAffineTransform()
    transform.translateX(by: rect.minX, yBy: rect.midY + glyphBounds.height * scale / 2)
    transform.scaleX(by: scale, yBy: -scale)
    transform.translateX(by: -glyphBounds.minX, yBy: -glyphBounds.minY)
    let path = whalePath()
    path.transform(using: transform as AffineTransform)
    return path
}

func render(pixels: Int, draw: (NSRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func drawAppIcon(in canvas: NSRect) {
    let unit = canvas.width / 1024
    // macOS icon grid: 824 pt rounded square centred on a 1024 canvas.
    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 18 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -8 * unit)
    shadow.set()
    NSColor(srgbRed: 0.27, green: 0.40, blue: 0.98, alpha: 1).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.30, green: 0.42, blue: 0.99, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.30, blue: 0.86, alpha: 1),
    ])!
    gradient.draw(in: tilePath, angle: -90)

    // Soft highlight across the top half.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
    highlight.draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let glyphWidth = 560 * unit
    let glyphRect = NSRect(x: canvas.midX - glyphWidth / 2 + 8 * unit, y: canvas.midY - 6 * unit - glyphWidth / 2,
                           width: glyphWidth, height: glyphWidth)
    let whale = placedWhale(in: glyphRect)
    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor(srgbRed: 0.05, green: 0.10, blue: 0.40, alpha: 0.35)
    glyphShadow.shadowBlurRadius = 14 * unit
    glyphShadow.shadowOffset = NSSize(width: 0, height: -6 * unit)
    glyphShadow.set()
    NSColor.white.setFill()
    whale.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawStatusIcon(in canvas: NSRect) {
    let inset = canvas.width * 0.04
    let whale = placedWhale(in: canvas.insetBy(dx: inset, dy: inset))
    NSColor.black.setFill()
    whale.fill()
}

func write(_ data: Data, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
}

func writeJSON(_ object: Any, to url: URL) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    write(data, to: url)
}

// App icon
let appIconDir = assets.appending(path: "AppIcon.appiconset")
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        write(render(pixels: points * scale, draw: drawAppIcon), to: appIconDir.appending(path: name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
writeJSON(["images": images, "info": ["author": "xcode", "version": 1]], to: appIconDir.appending(path: "Contents.json"))

// Menu bar icon (template)
let statusDir = assets.appending(path: "StatusBarIcon.imageset")
write(render(pixels: 18, draw: drawStatusIcon), to: statusDir.appending(path: "status.png"))
write(render(pixels: 36, draw: drawStatusIcon), to: statusDir.appending(path: "status@2x.png"))
writeJSON([
    "images": [
        ["filename": "status.png", "idiom": "mac", "scale": "1x"],
        ["filename": "status@2x.png", "idiom": "mac", "scale": "2x"],
    ],
    "info": ["author": "xcode", "version": 1],
    "properties": ["template-rendering-intent": "template"],
], to: statusDir.appending(path: "Contents.json"))

print("Icons written to \(assets.path)")
