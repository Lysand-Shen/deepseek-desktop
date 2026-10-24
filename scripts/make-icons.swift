#!/usr/bin/env swift
// Renders the app icon and the menu bar template icon into the asset catalog from the
// official DeepSeek logo (deepseek-logo.svg, the favicon of chat.deepseek.com).
// Usage: swift scripts/make-icons.swift DeepSeekNative/Resources/Assets.xcassets
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icons.swift <Assets.xcassets>\n".utf8))
    exit(1)
}
let assets = URL(fileURLWithPath: CommandLine.arguments[1])
let logoURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "deepseek-logo.svg")
let brandBlue = NSColor(srgbRed: 0x4D / 255, green: 0x6B / 255, blue: 0xFE / 255, alpha: 1)

/// Parses the logo's single `<path d="…">` (absolute M/L/C/Z commands) in SVG units, y pointing down.
func loadLogo() -> NSBezierPath {
    let svg = try! String(contentsOf: logoURL, encoding: .utf8)
    let d = String(svg.firstMatch(of: try! Regex(#"\sd="([^"]+)""#))!.output[1].substring!)
    let tokens = d.matches(of: try! Regex(#"[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#)).map { String(d[$0.range]) }
    var index = 0
    func number() -> CGFloat {
        defer { index += 1 }
        return CGFloat(Double(tokens[index])!)
    }
    func point() -> NSPoint { NSPoint(x: number(), y: number()) }

    let path = NSBezierPath()
    var command = ""
    while index < tokens.count {
        if tokens[index].first!.isLetter {
            command = tokens[index]
            index += 1
        }
        switch command {
        case "M":
            path.move(to: point())
            command = "L" // Further coordinate pairs are implicit line-tos.
        case "L":
            path.line(to: point())
        case "C":
            let control1 = point(), control2 = point()
            path.curve(to: point(), controlPoint1: control1, controlPoint2: control2)
        case "Z":
            path.close()
        default:
            fatalError("Unsupported SVG path command \(command)")
        }
    }
    path.windingRule = .nonZero // The eye and fin are cut out by opposite winding.
    return path
}
let logo = loadLogo()

/// The logo scaled to `width` and centred on `center`, flipped into AppKit's y-up space.
func placedLogo(width: CGFloat, center: NSPoint) -> NSBezierPath {
    let path = logo.copy() as! NSBezierPath
    let bounds = path.bounds
    let scale = width / bounds.width
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.scaleX(by: scale, yBy: -scale)
    transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
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

/// Like DeepSeek's own app icon: the blue whale on a white tile.
func drawAppIcon(in canvas: NSRect) {
    let unit = canvas.width / 1024
    // macOS icon grid: 824 pt rounded square centred on a 1024 canvas.
    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 18 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -8 * unit)
    shadow.set()
    NSColor.white.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // A faint cool shade towards the bottom keeps the tile from looking flat.
    let gradient = NSGradient(colors: [
        NSColor.white,
        NSColor(srgbRed: 0.94, green: 0.95, blue: 0.99, alpha: 1),
    ])!
    gradient.draw(in: tilePath, angle: -90)

    brandBlue.setFill()
    placedLogo(width: 520 * unit, center: NSPoint(x: canvas.midX + 6 * unit, y: canvas.midY)).fill()
}

func drawStatusIcon(in canvas: NSRect) {
    NSColor.black.setFill()
    placedLogo(width: canvas.width * 0.96, center: NSPoint(x: canvas.midX, y: canvas.midY)).fill()
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

// Whale glyph (template) for the quick chat bar, drawn larger than the menu bar icon.
let glyphDir = assets.appending(path: "WhaleGlyph.imageset")
for (scale, pixels) in [(1, 24), (2, 48), (3, 72)] {
    write(render(pixels: pixels, draw: drawStatusIcon), to: glyphDir.appending(path: "whale@\(scale)x.png"))
}
writeJSON([
    "images": [1, 2, 3].map { ["filename": "whale@\($0)x.png", "idiom": "universal", "scale": "\($0)x"] },
    "info": ["author": "xcode", "version": 1],
    "properties": ["template-rendering-intent": "template"],
], to: glyphDir.appending(path: "Contents.json"))

print("Icons written to \(assets.path)")
