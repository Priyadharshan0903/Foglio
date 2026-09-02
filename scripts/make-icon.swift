#!/usr/bin/env swift
import AppKit

// Generates build/Foglio.icns.
//
// The mark is the design's own "Daylog" candidate (Name and Icon.dc.html:86) —
// a ruled sheet with a tick — which suits Foglio, Italian for "sheet". It's
// drawn here rather than committed as a binary so it stays reviewable and
// regenerable, the same reasoning as the in-app icons.
//
// Colours are the product palette: the app's ink as the ground, paper for the
// sheet, and the amber accent on the tick so it reads at 16pt.

let ink = NSColor(srgbRed: 0x1A / 255, green: 0x1E / 255, blue: 0x22 / 255, alpha: 1)
let paper = NSColor(srgbRed: 0xF1 / 255, green: 0xF2 / 255, blue: 0xF3 / 255, alpha: 1)
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
    cg.setFillColor(ink.cgColor)
    cg.fillPath()

    cg.setLineWidth(5)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)

    // Sheet body and its ruled header, plus the two tabs above it.
    cg.setStrokeColor(paper.cgColor)
    cg.addRect(CGRect(x: 24, y: 30, width: 48, height: 40))
    cg.move(to: CGPoint(x: 24, y: 42)); cg.addLine(to: CGPoint(x: 72, y: 42))
    cg.move(to: CGPoint(x: 36, y: 22)); cg.addLine(to: CGPoint(x: 36, y: 30))
    cg.move(to: CGPoint(x: 60, y: 22)); cg.addLine(to: CGPoint(x: 60, y: 30))
    cg.strokePath()

    // The one thing done.
    cg.setStrokeColor(amber.cgColor)
    cg.move(to: CGPoint(x: 36, y: 56))
    cg.addLine(to: CGPoint(x: 42, y: 62))
    cg.addLine(to: CGPoint(x: 54, y: 48))
    cg.strokePath()
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
