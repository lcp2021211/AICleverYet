import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let rect = NSRect(x: 40, y: 40, width: 944, height: 944)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 215, yRadius: 215)
        NSGradient(starting: NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.21, alpha: 1),
                   ending: NSColor(calibratedRed: 0.03, green: 0.10, blue: 0.14, alpha: 1))!.draw(in: shape, angle: -60)
        NSColor(calibratedRed: 0.35, green: 0.95, blue: 0.76, alpha: 0.16).setStroke()
        for radius: CGFloat in [240, 350] {
            let circle = NSBezierPath(ovalIn: NSRect(x: 512-radius, y: 512-radius, width: radius*2, height: radius*2))
            circle.lineWidth = 4
            circle.stroke()
        }
        NSColor(calibratedRed: 0.42, green: 0.96, blue: 0.78, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 218, y: 475))
        for (x,y) in [(355,475),(437,660),(539,352),(637,560),(710,475),(806,475)] {
            path.line(to: NSPoint(x: x, y: y))
        }
        path.lineWidth = 43
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
