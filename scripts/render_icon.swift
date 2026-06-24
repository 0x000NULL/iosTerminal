// Renders the app icon: a green terminal prompt ">" + block cursor on a near-black square.
// Run: swift scripts/render_icon.swift <output.png>
// iOS app icons must be opaque (no alpha) — we use an opaque bitmap context.
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("ctx")
}

func color(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}
let bg = color(0x0B, 0x0F, 0x0A)
let green = color(0x3D, 0xFF, 0x88)

// Background (full square; iOS applies the rounded-corner mask).
ctx.setFillColor(bg)
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// Subtle inner vignette for depth.
ctx.setFillColor(color(0x10, 0x16, 0x12))
ctx.fillEllipse(in: CGRect(x: 140, y: 140, width: 744, height: 744))
ctx.setFillColor(bg)
ctx.fillEllipse(in: CGRect(x: 175, y: 175, width: 674, height: 674))

// Composition centered around y = 512.
let cy: CGFloat = 512
ctx.setStrokeColor(green)
ctx.setFillColor(green)
ctx.setLineWidth(72)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// ">" chevron (points right).
let chevLeft: CGFloat = 330
let chevTip: CGFloat = 540
let half: CGFloat = 150
ctx.move(to: CGPoint(x: chevLeft, y: cy + half))
ctx.addLine(to: CGPoint(x: chevTip, y: cy))
ctx.addLine(to: CGPoint(x: chevLeft, y: cy - half))
ctx.strokePath()

// Block cursor to the right.
let cursor = CGRect(x: 600, y: cy - 150, width: 118, height: 300)
let path = CGPath(roundedRect: cursor, cornerWidth: 16, cornerHeight: 16, transform: nil)
ctx.addPath(path)
ctx.fillPath()

guard let img = ctx.makeImage() else { fatalError("image") }
let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, img, nil)
if CGImageDestinationFinalize(dest) {
    print("wrote \(outPath) (\(S)x\(S))")
} else {
    fatalError("finalize")
}
