// Draws the Knobs app icon (DESIGN.md, "Icon concept") as an Icon Composer bundle for macOS 26.
//   swift scripts/make-icon.swift App/AppIcon.icon
// The bundle holds three layers over a graphite fill: tick marks, the knob, and the orange indicator. The
// system adds the glass, highlights and shadows, and tints each layer separately in tinted and clear modes,
// which a flat PNG icon can't get.
import AppKit

/// Layers are full-bleed on a 1024-point canvas; the system masks them to the icon shape.
let canvas = 1024
let center = CGPoint(x: 512, y: 512)
/// The dial sweeps 270°, from 7:30 round to 4:30, clockwise.
let sweepStart: CGFloat = 225
let sweepLength: CGFloat = 270
/// The indicator sits at two o'clock; ticks up to it are lit.
let indicatorAngle: CGFloat = 30
let signal = NSColor(srgbRed: 1, green: 0x5B / 255, blue: 0x1F / 255, alpha: 1)

func point(atAngle degrees: CGFloat, radius: CGFloat) -> CGPoint {
    let radians = degrees * .pi / 180
    return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
}

func white(_ level: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    NSColor(white: level, alpha: alpha).cgColor
}

func srgb(_ hex: Int) -> CGColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1
    ).cgColor
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func circle(radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

func drawTicks(in context: CGContext) {
    let tickCount = 28
    context.setLineCap(.round)
    for index in 0..<tickCount {
        let progress = CGFloat(index) / CGFloat(tickCount - 1)
        let isMajor = index % 3 == 0
        let isLit = progress * sweepLength <= sweepStart - indicatorAngle + 0.5
        let angle = sweepStart - progress * sweepLength
        context.setLineWidth(isMajor ? 19 : 11)
        context.setStrokeColor(isLit ? signal.withAlphaComponent(isMajor ? 1 : 0.8).cgColor : white(0.62, 0.45))
        context.move(to: point(atAngle: angle, radius: isMajor ? 395 : 412))
        context.addLine(to: point(atAngle: angle, radius: 450))
        context.strokePath()
    }
}

func drawKnob(in context: CGContext) {
    // Knurled outer ring.
    context.addEllipse(in: circle(radius: 333))
    context.setFillColor(srgb(0x121110))
    context.fillPath()
    context.setLineWidth(6)
    for index in 0..<120 {
        let angle = CGFloat(index) * 3
        let level = 0.16 + 0.10 * max(0, sin((angle - 45) * .pi / 180))
        context.setStrokeColor(white(level, 0.9))
        context.move(to: point(atAngle: angle, radius: 296))
        context.addLine(to: point(atAngle: angle, radius: 328))
        context.strokePath()
    }

    // Machined cap: a top-lit radial gradient with a brushed sheen of one-degree wedges whose brightness rises
    // and falls four times round the cap.
    let capRadius: CGFloat = 288
    context.saveGState()
    context.addEllipse(in: circle(radius: capRadius))
    context.clip()
    context.drawRadialGradient(
        gradient([srgb(0x5E5B55), srgb(0x34322F), srgb(0x22211F)]),
        startCenter: CGPoint(x: 422, y: 671), startRadius: 0, endCenter: center, endRadius: capRadius * 1.15,
        options: [.drawsAfterEndLocation])
    for degree in 0..<360 {
        let angle = CGFloat(degree)
        let brightness = pow(0.5 + 0.5 * cos(4 * (angle - 36) * .pi / 180), 3)
        context.setFillColor(white(1, 0.09 * brightness))
        context.move(to: center)
        context.addLine(to: point(atAngle: angle, radius: capRadius))
        context.addLine(to: point(atAngle: angle + 1.05, radius: capRadius))
        context.closePath()
        context.fillPath()
    }
    context.restoreGState()
}

func drawIndicator(in context: CGContext) {
    context.setStrokeColor(signal.cgColor)
    context.setLineWidth(50)
    context.setLineCap(.round)
    context.move(to: point(atAngle: indicatorAngle, radius: 139))
    context.addLine(to: point(atAngle: indicatorAngle, radius: 244))
    context.strokePath()
}

func writeLayer(_ name: String, to assets: URL, draw: (CGContext) -> Void) throws {
    guard
        let context = CGContext(
            data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }
    draw(context)
    let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    try png.write(to: assets.appendingPathComponent("\(name).png"))
}

/// Groups are listed top first. Only the indicator is glass, so it catches the light like a lens.
let iconJSON = """
    {
      "fill" : {
        "linear-gradient" : [
          "srgb:0.22745,0.21961,0.20392,1.00000",
          "srgb:0.08627,0.08235,0.07843,1.00000"
        ]
      },
      "groups" : [
        {
          "layers" : [ { "glass" : true, "image-name" : "indicator.png", "name" : "indicator" } ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
          "translucency" : { "enabled" : false, "value" : 0.5 }
        },
        {
          "layers" : [ { "glass" : false, "image-name" : "knob.png", "name" : "knob" } ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.6 }
        },
        {
          "layers" : [ { "glass" : false, "image-name" : "ticks.png", "name" : "ticks" } ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.3 }
        }
      ],
      "supported-platforms" : { "squares" : [ "macOS" ] }
    }

    """

let arguments = CommandLine.arguments
guard arguments.count == 2, arguments[1].hasSuffix(".icon") else {
    FileHandle.standardError.write("usage: swift scripts/make-icon.swift <path>/AppIcon.icon\n".data(using: .utf8)!)
    exit(64)
}
let bundle = URL(fileURLWithPath: arguments[1], isDirectory: true)
let assets = bundle.appendingPathComponent("Assets", isDirectory: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try writeLayer("ticks", to: assets, draw: drawTicks)
try writeLayer("knob", to: assets, draw: drawKnob)
try writeLayer("indicator", to: assets, draw: drawIndicator)
try iconJSON.write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(bundle.path)")
