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
        NSGradient(starting: NSColor(calibratedRed: 0.38, green: 0.64, blue: 1, alpha: 1),
                   ending: NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.78, alpha: 1))!.draw(in: shape, angle: -65)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let inset = NSBezierPath(roundedRect: NSRect(x: 145, y: 145, width: 734, height: 734), xRadius: 150, yRadius: 150)
        inset.lineWidth = 10
        inset.stroke()
        NSColor.white.setFill()
        let eyes = NSAffineTransform()
        eyes.translateX(by: 512, yBy: 512)
        eyes.rotate(byDegrees: 8)
        eyes.translateX(by: -512, yBy: -512)
        eyes.concat()
        NSBezierPath(roundedRect: NSRect(x: 375, y: 385, width: 73, height: 250), xRadius: 36, yRadius: 36).fill()
        NSBezierPath(roundedRect: NSRect(x: 565, y: 460, width: 73, height: 180), xRadius: 36, yRadius: 36).fill()
        NSBezierPath(ovalIn: NSRect(x: 769, y: 781, width: 62, height: 62)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
