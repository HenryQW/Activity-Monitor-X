// Render Packaging/AppIcon.icns and website/public/icon.png (a chip whose die shows two app colours over time, on a dark
// tile, on Apple's 1024 px grid): swift Scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Drawn in a 120 pt tile with the y axis down, scaled onto the 824 px body of the 1024 px grid.
func render(_ px: Int, small: Bool = false) -> Data {
    let k = CGFloat(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 100 * k, y: CGFloat(px) - 100 * k)
    ctx.scaleBy(x: 824 * k / 120, y: -824 * k / 120)
    func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat(hex >> 16) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 120, height: 120), cornerWidth: 27, cornerHeight: 27, transform: nil)
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(0x2A2D36), rgb(0x14161B)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 120), options: [])
    ctx.restoreGState()

    // The pins: three a side, two at small sizes, where three run together.
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.55))
    ctx.setLineWidth(small ? 6 : 4)
    ctx.setLineCap(.round)
    for p in small ? [48.0, 72] : [44.0, 60, 76] {
        for (a, b) in [(14.0, 24.0), (96.0, 106.0)] {
            ctx.strokeLineSegments(between: [CGPoint(x: p, y: a), CGPoint(x: p, y: b)])
            ctx.strokeLineSegments(between: [CGPoint(x: a, y: p), CGPoint(x: b, y: p)])
        }
    }

    // The die, and on it the history: two app colours stacked over time.
    let die = CGPath(roundedRect: CGRect(x: 26, y: 26, width: 68, height: 68), cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.addPath(die)
    ctx.setFillColor(rgb(0x1F222A))
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(die)
    ctx.clip()
    func band(_ top: [CGFloat], _ color: CGColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 26, y: 94))
        path.addLine(to: CGPoint(x: 26, y: top[0]))
        path.addCurve(to: CGPoint(x: 58, y: top[3]), control1: CGPoint(x: 40, y: top[1]), control2: CGPoint(x: 46, y: top[2]))
        path.addCurve(to: CGPoint(x: 94, y: top[6]), control1: CGPoint(x: 68, y: top[4]), control2: CGPoint(x: 76, y: top[5]))
        path.addLine(to: CGPoint(x: 94, y: 94))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }
    band([74, 70, 78, 66, 56, 66, 46], rgb(0x378ADD))
    band([84, 82, 86, 80, 74, 80, 70], rgb(0x5DCAA5))
    ctx.restoreGState()
    ctx.addPath(die)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.6))
    ctx.setLineWidth(small ? 4 : 2.5)
    ctx.strokePath()

    // A hairline rim, as the system draws on a dark icon.
    ctx.addPath(tile)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.18))
    ctx.setLineWidth(1.5)
    ctx.strokePath()

    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size, small: size <= 32).write(to: set.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, small: size == 16).write(to: set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(512).write(to: URL(fileURLWithPath: "website/public/icon.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", "Packaging/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: set)
exit(iconutil.terminationStatus)
