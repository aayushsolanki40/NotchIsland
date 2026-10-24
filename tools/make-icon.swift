#!/usr/bin/env swift
// Draws the NotchIsland app icon ("art bubble": a pill with equalizer bars plus a
// separate bubble holding album art) and writes a macOS .iconset folder.
//
// Usage: swift tools/make-icon.swift <output.iconset> [preview.png]
//        iconutil -c icns <output.iconset> -o Resources/AppIcon.icns
import AppKit

func hex(_ value: UInt32) -> CGColor {
    CGColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

/// Draws the icon on a `size` x `size` canvas. Design units are 0...100 with y pointing down.
func drawIcon(in ctx: CGContext, size: CGFloat) {
    // macOS icon grid: the artwork fills 824 of 1024 points, leaving room for the shadow.
    let body = size * 824 / 1024
    let inset = (size - body) / 2
    ctx.translateBy(x: inset, y: size - inset)
    ctx.scaleBy(x: body / 100, y: -body / 100)

    let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                      cornerWidth: 22.37, cornerHeight: 22.37, transform: nil)

    // Soft drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -1.2), blur: 2.6, color: CGColor(gray: 0, alpha: 0.35))
    ctx.setFillColor(hex(0x34344A))
    ctx.addPath(tile)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()

    // A faint top-to-bottom sheen gives the tile a little depth.
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(gray: 1, alpha: 0.09), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 50, y: 0), end: CGPoint(x: 50, y: 100), options: [])

    // Shrink the artwork a touch around the centre so it sits comfortably inside the tile.
    ctx.translateBy(x: 50, y: 50)
    ctx.scaleBy(x: 0.94, y: 0.94)
    ctx.translateBy(x: -52, y: -50)   // -52 also centres the pill + bubble pair horizontally

    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                           cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.fillPath()
    }

    let black = hex(0x000000)
    rounded(12, 38, 48, 24, 12, black)                    // the pill
    let bars: [(x: CGFloat, h: CGFloat)] = [(22, 8), (30, 14), (38, 10), (46, 6)]
    for bar in bars { rounded(bar.x, 50 - bar.h / 2, 4, bar.h, 2, hex(0xFF9F0A)) }

    ctx.setFillColor(black)                                // the bubble
    ctx.fillEllipse(in: CGRect(x: 64, y: 36, width: 28, height: 28))

    // Album art inside the bubble: a diagonal pink-to-purple cover with a tiny music note.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 71, y: 43, width: 14, height: 14),
                       cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.clip()
    let cover = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [hex(0xFF5C7A), hex(0xB44DE0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(cover, start: CGPoint(x: 71, y: 43), end: CGPoint(x: 85, y: 57), options: [])
    ctx.restoreGState()
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 74.2, y: 51, width: 3.6, height: 3))     // note head
    ctx.fill(CGRect(x: 77, y: 46, width: 0.9, height: 6))                  // stem
    ctx.fill(CGRect(x: 77, y: 46, width: 3.4, height: 1.1))                // flag
    ctx.restoreGState()
}

func renderPNG(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    gc.imageInterpolation = .high
    drawIcon(in: gc.cgContext, size: CGFloat(size))
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset> [preview.png]\n".utf8))
    exit(1)
}
let dir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let files: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                              ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                              ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in files {
    try renderPNG(size: px).write(to: dir.appendingPathComponent("icon_\(name).png"))
}
if args.count >= 3 { try renderPNG(size: 1024).write(to: URL(fileURLWithPath: args[2])) }
print("Wrote \(files.count) sizes to \(dir.path)")
