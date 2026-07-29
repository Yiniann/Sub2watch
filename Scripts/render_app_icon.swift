import AppKit

private let canvasSize = 1024
private let arguments = Array(CommandLine.arguments.dropFirst())
private let outputPath = arguments.first ?? "AppIcon-1024.png"
private let appearance = arguments.dropFirst().first ?? "dark"
private let isLight = appearance == "light"

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

private func strokeArc(
    center: NSPoint,
    radius: CGFloat,
    startAngle: CGFloat,
    endAngle: CGFloat,
    width: CGFloat,
    stroke: NSColor
) {
    let path = NSBezierPath()
    path.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: startAngle,
        endAngle: endAngle,
        clockwise: false
    )
    path.lineWidth = width
    path.lineCapStyle = .round
    stroke.setStroke()
    path.stroke()
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let bitmapContext = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: canvasSize * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Unable to create app icon canvas")
}
let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

color(isLight ? 0xFFFFFF : 0x15181D).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)).fill()

let center = NSPoint(x: 512, y: 512)
strokeArc(
    center: center,
    radius: 286,
    startAngle: -58,
    endAngle: 230,
    width: 78,
    stroke: color(0x34C759)
)
strokeArc(
    center: center,
    radius: 185,
    startAngle: -58,
    endAngle: 176,
    width: 60,
    stroke: color(0xAF52DE)
)

let sparkle = NSBezierPath()
sparkle.move(to: NSPoint(x: 512, y: 622))
sparkle.line(to: NSPoint(x: 538, y: 538))
sparkle.line(to: NSPoint(x: 622, y: 512))
sparkle.line(to: NSPoint(x: 538, y: 486))
sparkle.line(to: NSPoint(x: 512, y: 402))
sparkle.line(to: NSPoint(x: 486, y: 486))
sparkle.line(to: NSPoint(x: 402, y: 512))
sparkle.line(to: NSPoint(x: 486, y: 538))
sparkle.close()
color(isLight ? 0x15181D : 0xF7F9FA).setFill()
sparkle.fill()

NSGraphicsContext.restoreGraphicsState()

guard let cgImage = bitmapContext.makeImage(),
      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode app icon")
}

let outputURL = URL(fileURLWithPath: outputPath)
try png.write(to: outputURL)
