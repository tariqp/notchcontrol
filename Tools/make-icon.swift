// Draws the NotchControl app icon (a dark rounded tile with a notch and an orange starburst)
// into an .iconset folder. Usage: swift Tools/make-icon.swift <out.iconset>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size
    let tile = NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88), xRadius: s * 0.2, yRadius: s * 0.2)
    NSColor(calibratedWhite: 0.09, alpha: 1).setFill(); tile.fill()
    NSColor(calibratedWhite: 0.3, alpha: 1).setStroke(); tile.lineWidth = s * 0.012; tile.stroke()
    // the notch: a pill hanging from the top edge
    let notch = NSBezierPath(roundedRect: NSRect(x: s * 0.3, y: s * 0.76, width: s * 0.4, height: s * 0.18), xRadius: s * 0.06, yRadius: s * 0.06)
    NSColor.black.setFill(); notch.fill()
    // starburst
    let c = NSPoint(x: s * 0.5, y: s * 0.44)
    let outer = s * 0.26, inner = s * 0.11
    let star = NSBezierPath()
    for i in 0..<16 {
        let r = i % 2 == 0 ? outer : inner
        let a = CGFloat(i) / 16 * .pi * 2 + .pi / 2
        let p = NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        if i == 0 { star.move(to: p) } else { star.line(to: p) }
    }
    star.close()
    NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).setFill(); star.fill()
    img.unlockFocus()
    return img
}

for (px, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
                   (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
                   (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
    let img = draw(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { continue }
    rep.size = NSSize(width: px, height: px)
    let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: png)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try? png.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
}
