#!/usr/bin/env swift
import AppKit

// Generates build/Foglio.icns.
//
// The mark is the design's own "Margin" candidate (Name and Icon.dc.html:92) —
// a ruled margin line with notes beside it, tagged "notes-first" — which fits
// this app better than the previous "Daylog" sheet-and-tick mark once Notes
// became the main surface. It's drawn here rather than committed as a binary
// so it stays reviewable and regenerable, the same reasoning as the in-app
// icons.
//
// Colours and geometry are copied verbatim from the design's candidate list:
// paper ground, ink strokes, amber dot marking where the margin line and the
// middle note line meet.

let paper = NSColor(srgbRed: 0xF7 / 255, green: 0xF8 / 255, blue: 0xF8 / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x1A / 255, green: 0x1E / 255, blue: 0x22 / 255, alpha: 1)
let amber = NSColor(srgbRed: 0xE0 / 255, green: 0x9A / 255, blue: 0x2B / 255, alpha: 1)

/// Draws the mark in a 96x96 space, top-left origin (SVG convention).
func draw(into cg: CGContext, pixels: CGFloat) {
    let scale = pixels / 96
    cg.translateBy(x: 0, y: pixels)
    cg.scaleBy(x: scale, y: -scale)

    // Ground: a rounded square inset from the canvas, as macOS icons are.
    let plate = CGRect(x: 7, y: 7, width: 82, height: 82)
    let rounded = CGPath(roundedRect: plate, cornerWidth: 20, cornerHeight: 20, transform: nil)
    cg.addPath(rounded)
    cg.setFillColor(paper.cgColor)
    cg.fillPath()

    // The design uses a thicker stroke (7 vs. 5 units) once it's rendered
    // small — at a uniform scale the four thin strokes thin out to under a
    // pixel by 16x16 and the mark disappears.
    cg.setLineWidth(pixels <= 32 ? 7 : 5)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(ink.cgColor)

    // The margin rule, and three note lines beside it — "M36 20v56 M48 34h28
    // M48 48h28 M48 62h18" (Name and Icon.dc.html:93).
    cg.move(to: CGPoint(x: 36, y: 20)); cg.addLine(to: CGPoint(x: 36, y: 76))
    cg.move(to: CGPoint(x: 48, y: 34)); cg.addLine(to: CGPoint(x: 76, y: 34))
    cg.move(to: CGPoint(x: 48, y: 48)); cg.addLine(to: CGPoint(x: 76, y: 48))
    cg.move(to: CGPoint(x: 48, y: 62)); cg.addLine(to: CGPoint(x: 66, y: 62))
    cg.strokePath()

    // Where you are on the margin — the one accent, sitting on the rule line.
    cg.setFillColor(amber.cgColor)
    cg.fillEllipse(in: CGRect(x: 30, y: 42, width: 12, height: 12))
}

func render(_ pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(into: context.cgContext, pixels: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/Foglio.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The names iconutil expects.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let png = render(variant.pixels) else {
        FileHandle.standardError.write("failed to render \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try png.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

print("wrote \(variants.count) sizes to \(iconset.path)")
