import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDirectory = root.appendingPathComponent("Resources")
let iconsetDirectory = resourcesDirectory.appendingPathComponent("AppIcon.iconset")
let outputIcon = resourcesDirectory.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

func drawIcon(pixelSize: Int, output: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let context = NSGraphicsContext.current?.cgContext else {
        throw NSError(domain: "Icon", code: 1)
    }

    context.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)
    context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    let baseRect = NSRect(x: 64, y: 64, width: 896, height: 896)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: 196, yRadius: 196)
    NSColor.black.withAlphaComponent(0.28).setFill()
    NSBezierPath(roundedRect: baseRect.offsetBy(dx: 0, dy: -18), xRadius: 196, yRadius: 196).fill()

    NSGraphicsContext.saveGraphicsState()
    basePath.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.055, green: 0.071, blue: 0.110, alpha: 1),
        NSColor(calibratedRed: 0.020, green: 0.027, blue: 0.045, alpha: 1)
    ])!.draw(in: baseRect, angle: 315)

    NSColor(calibratedWhite: 1, alpha: 0.06).setStroke()
    let grid = NSBezierPath()
    for x in stride(from: 128, through: 896, by: 128) {
        grid.move(to: NSPoint(x: x, y: 96))
        grid.line(to: NSPoint(x: x, y: 928))
    }
    for y in stride(from: 128, through: 896, by: 128) {
        grid.move(to: NSPoint(x: 96, y: y))
        grid.line(to: NSPoint(x: 928, y: y))
    }
    grid.lineWidth = 2
    grid.stroke()

    let ringRect = NSRect(x: 192, y: 184, width: 640, height: 640)
    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    let ringBack = NSBezierPath(ovalIn: ringRect)
    ringBack.lineWidth = 34
    ringBack.stroke()

    let ring = NSBezierPath()
    ring.appendArc(
        withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
        radius: ringRect.width / 2,
        startAngle: 92,
        endAngle: 382,
        clockwise: false
    )
    NSColor(calibratedRed: 0.31, green: 0.76, blue: 0.83, alpha: 1).setStroke()
    ring.lineWidth = 34
    ring.lineCapStyle = .round
    ring.stroke()

    NSColor(calibratedWhite: 1, alpha: 0.28).setStroke()
    let hand = NSBezierPath()
    hand.move(to: NSPoint(x: 512, y: 512))
    hand.line(to: NSPoint(x: 512, y: 690))
    hand.move(to: NSPoint(x: 512, y: 512))
    hand.line(to: NSPoint(x: 646, y: 456))
    hand.lineWidth = 18
    hand.lineCapStyle = .round
    hand.stroke()

    NSColor(calibratedRed: 0.58, green: 0.95, blue: 0.64, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 486, y: 486, width: 52, height: 52)).fill()

    NSColor(calibratedWhite: 1, alpha: 0.82).setStroke()
    let tickPath = NSBezierPath()
    for hour in 0..<12 {
        let angle = (Double(hour) / 12.0) * Double.pi * 2.0 + Double.pi / 2.0
        let outer = NSPoint(
            x: 512 + CGFloat(cos(angle)) * 282,
            y: 512 + CGFloat(sin(angle)) * 282
        )
        let inner = NSPoint(
            x: 512 + CGFloat(cos(angle)) * (hour % 3 == 0 ? 232 : 250),
            y: 512 + CGFloat(sin(angle)) * (hour % 3 == 0 ? 232 : 250)
        )
        tickPath.move(to: outer)
        tickPath.line(to: inner)
    }
    tickPath.lineWidth = 10
    tickPath.lineCapStyle = .round
    tickPath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedWhite: 1, alpha: 0.15).setStroke()
    basePath.lineWidth = 4
    basePath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Icon", code: 2)
    }
    try png.write(to: output)
}

let specs: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

for (points, scale) in specs {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    let output = iconsetDirectory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    try drawIcon(pixelSize: points * scale, output: output)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDirectory.path, "-o", outputIcon.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "Icon", code: Int(process.terminationStatus))
}

print("Generated \(outputIcon.path)")
