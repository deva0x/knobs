// Draws the Knobs app icon (DESIGN.md, "Icon concept") into an asset catalog icon set.
//   swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset
// Every size is drawn from vector, not scaled down, so small sizes get fewer, bolder tick marks.
import AppKit

/// The design is laid out on Apple's 1024-point icon grid; everything below is in those units.
let grid: CGFloat = 1024
let bodyInset: CGFloat = 100
let bodyCornerRadius: CGFloat = 185
let center = CGPoint(x: 512, y: 512)
/// The dial sweeps 270°, from 7:30 round to 4:30, clockwise.
let sweepStart: CGFloat = 225
let sweepLength: CGFloat = 270
/// The indicator sits at two o'clock.
let indicatorAngle: CGFloat = 30
let signal = NSColor(srgbRed: 1, green: 0x5B / 255, blue: 0x1F / 255, alpha: 1)

struct IconSize {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
}

let sizes: [IconSize] = [16, 32, 128, 256, 512].flatMap { [IconSize(points: $0, scale: 1), IconSize(points: $0, scale: 2)] }

func point(atAngle degrees: CGFloat, radius: CGFloat) -> CGPoint {
    let radians = degrees * .pi / 180
    return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
}

func color(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    NSColor(white: white, alpha: alpha).cgColor
}

func warm(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: alpha).cgColor
}

func linearGradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func drawIcon(in context: CGContext, pixels: Int) {
    let isSmall = pixels <= 64
    context.scaleBy(x: CGFloat(pixels) / grid, y: CGFloat(pixels) / grid)

    // Base: a warm graphite rounded square with a soft shadow beneath.
    let bodyRect = CGRect(x: 0, y: 0, width: grid, height: grid).insetBy(dx: bodyInset, dy: bodyInset)
    let body = CGPath(
        roundedRect: bodyRect, cornerWidth: bodyCornerRadius, cornerHeight: bodyCornerRadius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0.35))
    context.addPath(body)
    context.setFillColor(warm(0x1C, 0x1B, 0x19))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(body)
    context.clip()
    context.drawLinearGradient(
        linearGradient([warm(0x3A, 0x38, 0x34), warm(0x1E, 0x1D, 0x1B), warm(0x16, 0x15, 0x14)]),
        start: CGPoint(x: 512, y: bodyRect.maxY), end: CGPoint(x: 512, y: bodyRect.minY), options: [])
    // A faint warm glow behind the lit side of the dial.
    context.drawRadialGradient(
        linearGradient([warm(0xFF, 0x5B, 0x1F, 0.16), warm(0xFF, 0x5B, 0x1F, 0)]),
        startCenter: point(atAngle: 60, radius: 170), startRadius: 0,
        endCenter: point(atAngle: 60, radius: 170), endRadius: 460, options: [])
    context.restoreGState()

    // Hairline highlight along the top edge of the base.
    context.saveGState()
    context.addPath(body)
    context.setLineWidth(isSmall ? 10 : 4)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        linearGradient([color(1, 0.22), color(1, 0.02)]),
        start: CGPoint(x: 512, y: bodyRect.maxY), end: CGPoint(x: 512, y: 512), options: [])
    context.restoreGState()

    // Tick marks round the dial. Ticks up to the indicator are lit in signal orange.
    let tickCount = isSmall ? 11 : 28
    let litLimit = sweepStart - indicatorAngle
    context.setLineCap(.round)
    for index in 0..<tickCount {
        let progress = CGFloat(index) / CGFloat(tickCount - 1)
        let angle = sweepStart - progress * sweepLength
        let isMajor = isSmall || index % 3 == 0
        let inner: CGFloat = isMajor ? 318 : 332
        context.setLineWidth(isSmall ? 30 : (isMajor ? 15 : 9))
        let isLit = progress * sweepLength <= litLimit + 0.5
        context.setStrokeColor(isLit ? signal.withAlphaComponent(isMajor ? 1 : 0.8).cgColor : color(0.62, 0.45))
        context.move(to: point(atAngle: angle, radius: inner))
        context.addLine(to: point(atAngle: angle, radius: 362))
        context.strokePath()
    }

    // Knurled outer ring of the knob.
    let ringRadius: CGFloat = 268
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0, 0.55))
    context.addEllipse(in: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
    context.setFillColor(warm(0x12, 0x11, 0x10))
    context.fillPath()
    context.restoreGState()
    if !isSmall {
        context.saveGState()
        context.setLineWidth(5)
        for index in 0..<120 {
            let angle = CGFloat(index) * 3
            let shade = 0.16 + 0.10 * max(0, sin((angle - 45) * .pi / 180))
            context.setStrokeColor(color(shade, 0.9))
            context.move(to: point(atAngle: angle, radius: 238))
            context.addLine(to: point(atAngle: angle, radius: ringRadius - 4))
            context.strokePath()
        }
        context.restoreGState()
    }

    // The machined cap: a brushed, conic sheen over a top-lit radial gradient.
    let capRadius: CGFloat = isSmall ? 250 : 232
    let capRect = CGRect(x: center.x - capRadius, y: center.y - capRadius, width: capRadius * 2, height: capRadius * 2)
    context.saveGState()
    context.addEllipse(in: capRect)
    context.clip()
    context.drawRadialGradient(
        linearGradient([warm(0x5E, 0x5B, 0x55), warm(0x34, 0x32, 0x2F), warm(0x22, 0x21, 0x1F)]),
        startCenter: CGPoint(x: 440, y: 640), startRadius: 0, endCenter: center, endRadius: capRadius * 1.15,
        options: [.drawsAfterEndLocation])
    if !isSmall {
        // Brushed-metal sheen: one-degree wedges whose brightness rises and falls four times round the cap.
        for degree in 0..<360 {
            let angle = CGFloat(degree)
            let brightness = pow(0.5 + 0.5 * cos(4 * (angle - 36) * .pi / 180), 3)
            context.setFillColor(color(1, 0.09 * brightness))
            context.move(to: center)
            context.addLine(to: point(atAngle: angle, radius: capRadius))
            context.addLine(to: point(atAngle: angle + 1.05, radius: capRadius))
            context.closePath()
            context.fillPath()
        }
    }
    context.restoreGState()

    // Bevel: light on the upper rim, dark on the lower.
    context.saveGState()
    context.addEllipse(in: capRect.insetBy(dx: 3, dy: 3))
    context.setLineWidth(isSmall ? 14 : 6)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        linearGradient([color(1, 0.38), color(1, 0.05), color(0, 0.4)]),
        start: CGPoint(x: 512, y: capRect.maxY), end: CGPoint(x: 512, y: capRect.minY), options: [])
    context.restoreGState()

    // The indicator, glowing slightly.
    context.saveGState()
    context.setShadow(offset: .zero, blur: isSmall ? 0 : 34, color: signal.withAlphaComponent(0.85).cgColor)
    context.setStrokeColor(signal.cgColor)
    context.setLineWidth(isSmall ? 64 : 40)
    context.setLineCap(.round)
    context.move(to: point(atAngle: indicatorAngle, radius: isSmall ? 90 : 112))
    context.addLine(to: point(atAngle: indicatorAngle, radius: isSmall ? 200 : 196))
    context.strokePath()
    context.restoreGState()
}

func writePNG(pixels: Int, to url: URL) throws {
    guard
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }
    drawIcon(in: context, pixels: pixels)
    let image = context.makeImage()!
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: url)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift scripts/make-icon.swift <AppIcon.appiconset folder>\n".data(using: .utf8)!)
    exit(64)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in sizes {
    try writePNG(pixels: size.pixels, to: folder.appendingPathComponent(size.filename))
    images.append([
        "filename": size.filename, "idiom": "mac", "scale": "\(size.scale)x", "size": "\(size.points)x\(size.points)",
    ])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: folder.appendingPathComponent("Contents.json"))
print("Wrote \(sizes.count) icon images to \(folder.path)")
