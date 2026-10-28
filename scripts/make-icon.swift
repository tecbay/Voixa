// Draws Voixa's app icon: waveform bars forming a "V" on a gradient tile.
// usage: swift scripts/make-icon.swift <output.png>   (1024×1024)
import AppKit

let size: CGFloat = 1024
// Draw into an exact-size bitmap (NSImage.lockFocus would render at 2x on Retina).
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824 pt tile centred on a 1024 canvas, ~185 pt corners.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(tilePath)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Gradient background: deep indigo (bottom-left) to violet (top-right).
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let colors = [
    NSColor(srgbRed: 0.16, green: 0.10, blue: 0.45, alpha: 1).cgColor,
    NSColor(srgbRed: 0.42, green: 0.22, blue: 0.85, alpha: 1).cgColor,
    NSColor(srgbRed: 0.85, green: 0.35, blue: 0.75, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.6, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.minY), end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])

// Subtle top highlight.
let highlight = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
ctx.drawLinearGradient(highlight, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.midY), options: [])

// Waveform bars: heights fall towards the centre so the tops trace a "V".
let heights: [CGFloat] = [0.92, 0.70, 0.48, 0.28, 0.48, 0.70, 0.92]
let barWidth: CGFloat = 58
let gap: CGFloat = 34
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
let maxHeight: CGFloat = 520
let baseline = tile.midY - maxHeight / 2 + 10
var x = tile.midX - totalWidth / 2
for h in heights {
    let height = maxHeight * h
    // Bars sit on a common bottom line, like the arms of a V meeting low in the middle.
    let bar = CGRect(x: x, y: baseline, width: barWidth, height: height)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    x += barWidth + gap
}
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: NSColor.black.withAlphaComponent(0.25).cgColor)
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
