import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")

struct IconSlot {
    let filename: String
    let pixels: CGFloat
}

let slots: [IconSlot] = [
    .init(filename: "Icon-App-20x20@1x.png", pixels: 20),
    .init(filename: "Icon-App-20x20@2x.png", pixels: 40),
    .init(filename: "Icon-App-20x20@3x.png", pixels: 60),
    .init(filename: "Icon-App-29x29@1x.png", pixels: 29),
    .init(filename: "Icon-App-29x29@2x.png", pixels: 58),
    .init(filename: "Icon-App-29x29@3x.png", pixels: 87),
    .init(filename: "Icon-App-40x40@1x.png", pixels: 40),
    .init(filename: "Icon-App-40x40@2x.png", pixels: 80),
    .init(filename: "Icon-App-40x40@3x.png", pixels: 120),
    .init(filename: "Icon-App-60x60@2x.png", pixels: 120),
    .init(filename: "Icon-App-60x60@3x.png", pixels: 180),
    .init(filename: "Icon-App-76x76@1x.png", pixels: 76),
    .init(filename: "Icon-App-76x76@2x.png", pixels: 152),
    .init(filename: "Icon-App-83.5x83.5@2x.png", pixels: 167),
    .init(filename: "Icon-App-1024x1024@1x.png", pixels: 1024),
]

extension NSColor {
    convenience init(hex: Int) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

func roundedStrokePath(points: [(CGFloat, CGFloat)], width: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    guard let first = points.first else { return path }
    path.move(to: NSPoint(x: first.0, y: first.1))
    for point in points.dropFirst() {
        path.line(to: NSPoint(x: point.0, y: point.1))
    }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap for \(size)")
    }
    bitmap.size = NSSize(width: size, height: size)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create drawing context for \(size)")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    let scale = size / 1024
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    NSColor(hex: 0xF9F5EE).setFill()
    rect.fill()

    let glow = NSBezierPath(ovalIn: NSRect(x: 148 * scale, y: 118 * scale, width: 728 * scale, height: 728 * scale))
    NSColor(hex: 0xF3E9DD).withAlphaComponent(0.78).setFill()
    glow.fill()

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 36 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -18 * scale)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)

    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()

    let paper = NSBezierPath(
        roundedRect: NSRect(x: 242 * scale, y: 150 * scale, width: 536 * scale, height: 724 * scale),
        xRadius: 76 * scale,
        yRadius: 76 * scale
    )
    NSColor.white.setFill()
    paper.fill()

    NSGraphicsContext.current?.restoreGraphicsState()

    let stroke = NSColor(hex: 0x363633)
    let accent = NSColor(hex: 0xE8785D)
    let blue = NSColor(hex: 0x6BA0D9)
    let paperLine = NSColor(hex: 0xDED8CF)

    NSColor(hex: 0xFFFDF8).setFill()
    paper.fill()
    stroke.withAlphaComponent(0.9).setStroke()
    paper.lineWidth = 22 * scale
    paper.stroke()

    let binding = NSBezierPath(
        roundedRect: NSRect(x: 242 * scale, y: 150 * scale, width: 126 * scale, height: 724 * scale),
        xRadius: 76 * scale,
        yRadius: 76 * scale
    )
    accent.setFill()
    binding.fill()

    let bindingMask = NSBezierPath(rect: NSRect(x: 318 * scale, y: 150 * scale, width: 80 * scale, height: 724 * scale))
    NSGraphicsContext.current?.saveGraphicsState()
    bindingMask.setClip()
    NSColor(hex: 0xFFFDF8).setFill()
    paper.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    stroke.withAlphaComponent(0.9).setStroke()
    paper.lineWidth = 22 * scale
    paper.stroke()

    for y in [722, 638, 554, 470, 386] {
        paperLine.setStroke()
        let line = roundedStrokePath(points: [(430, CGFloat(y)), (690, CGFloat(y))], width: 24 * scale)
        line.stroke()
    }

    for y in [720, 604, 488, 372] {
        NSColor.white.withAlphaComponent(0.92).setFill()
        let hole = NSBezierPath(ovalIn: NSRect(x: 282 * scale, y: CGFloat(y) * scale, width: 58 * scale, height: 58 * scale))
        hole.fill()
        stroke.withAlphaComponent(0.18).setStroke()
        hole.lineWidth = 6 * scale
        hole.stroke()
    }

    blue.setStroke()
    for (index, y) in [284, 232, 180].enumerated() {
        let xOffset = CGFloat(index) * 18 * scale
        let breeze = NSBezierPath()
        breeze.move(to: NSPoint(x: 386 * scale + xOffset, y: CGFloat(y) * scale))
        breeze.curve(
            to: NSPoint(x: 706 * scale - xOffset, y: CGFloat(y + 10) * scale),
            controlPoint1: NSPoint(x: 492 * scale, y: CGFloat(y - 28) * scale),
            controlPoint2: NSPoint(x: 598 * scale, y: CGFloat(y + 38) * scale)
        )
        breeze.lineWidth = 18 * scale
        breeze.lineCapStyle = .round
        breeze.stroke()
    }

    return bitmap
}

func pngData(from bitmap: NSBitmapImageRep) -> Data? {
    return bitmap.representation(using: .png, properties: [:])
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

for slot in slots {
    let bitmap = drawIcon(size: slot.pixels)
    guard let data = pngData(from: bitmap) else {
        fatalError("Could not encode \(slot.filename)")
    }
    try data.write(to: iconSet.appendingPathComponent(slot.filename), options: .atomic)
}

print("Generated \(slots.count) iOS app icon assets in \(iconSet.path)")
