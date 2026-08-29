import AppKit

let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDirectory = repository.appendingPathComponent("Shared (App)/Assets.xcassets/AppIcon.appiconset")
let extensionIconDirectory = repository.appendingPathComponent("Shared (Extension)/Resources/images")

func drawIcon(size: Int, appearance: String = "standard") -> NSImage {
    let dimension = CGFloat(size)
    return NSImage(size: NSSize(width: dimension, height: dimension), flipped: false) { rect in
        NSGraphicsContext.current?.imageInterpolation = .high
        let inset = dimension * 0.035
        let tile = NSBezierPath(
            roundedRect: rect.insetBy(dx: inset, dy: inset),
            xRadius: dimension * 0.22,
            yRadius: dimension * 0.22
        )
        let base: NSColor
        switch appearance {
        case "dark": base = NSColor(srgbRed: 0.18, green: 0.18, blue: 0.38, alpha: 1)
        case "tinted": base = NSColor(srgbRed: 0.40, green: 0.40, blue: 0.40, alpha: 1)
        default: base = NSColor(srgbRed: 0.357, green: 0.357, blue: 0.839, alpha: 1)
        }
        base.setFill()
        tile.fill()

        let center = NSPoint(x: dimension * 0.5, y: dimension * 0.515)
        let radius = dimension * 0.285
        let stroke = max(1.4, dimension * 0.075)
        let white = NSColor.white.withAlphaComponent(0.96)

        let upperArc = NSBezierPath()
        upperArc.appendArc(withCenter: center, radius: radius, startAngle: 28, endAngle: 186)
        upperArc.lineWidth = stroke
        upperArc.lineCapStyle = .round
        white.setStroke()
        upperArc.stroke()

        let lowerArc = NSBezierPath()
        lowerArc.appendArc(withCenter: center, radius: radius, startAngle: 204, endAngle: 342)
        lowerArc.lineWidth = stroke
        lowerArc.lineCapStyle = .round
        white.setStroke()
        lowerArc.stroke()

        let check = NSBezierPath()
        check.move(to: NSPoint(x: dimension * 0.34, y: dimension * 0.50))
        check.line(to: NSPoint(x: dimension * 0.46, y: dimension * 0.38))
        check.line(to: NSPoint(x: dimension * 0.69, y: dimension * 0.64))
        check.lineWidth = stroke * 0.86
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        white.setStroke()
        check.stroke()
        return true
    }
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try writePNG(drawIcon(size: size), to: appIconDirectory.appendingPathComponent("app-icon-\(size).png"))
}
try writePNG(drawIcon(size: 1024, appearance: "dark"), to: appIconDirectory.appendingPathComponent("app-icon-1024-dark.png"))
try writePNG(drawIcon(size: 1024, appearance: "tinted"), to: appIconDirectory.appendingPathComponent("app-icon-1024-tinted.png"))

for size in [48, 64, 96, 128, 256, 512] {
    try writePNG(drawIcon(size: size), to: extensionIconDirectory.appendingPathComponent("icon-\(size).png"))
}
