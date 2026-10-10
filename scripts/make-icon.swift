#!/usr/bin/env swift
import AppKit

// Generates an iconset and PNG-backed ICNS file. The user selected "Refined
// Margin" from design/icon-concepts/comparison.png: warm ivory, charcoal ink,
// and one amber dot. Geometry matches that concept within a macOS icon inset.

let paper = NSColor(srgbRed: 0xF3 / 255, green: 0xEB / 255, blue: 0xDD / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x29 / 255, green: 0x25 / 255, blue: 0x1F / 255, alpha: 1)
let amber = NSColor(srgbRed: 0xDE / 255, green: 0xA9 / 255, blue: 0x58 / 255, alpha: 1)

/// Draws the mark in a 96x96 space, top-left origin (SVG convention).
func draw(into cg: CGContext, pixels: CGFloat) {
    let scale = pixels / 96
    cg.translateBy(x: 0, y: pixels)
    cg.scaleBy(x: scale, y: -scale)

    // Ground: a rounded square inset from the canvas, as macOS icons are.
    let plate = CGRect(x: 7, y: 7, width: 82, height: 82)
    let rounded = CGPath(roundedRect: plate, cornerWidth: 18.5, cornerHeight: 18.5, transform: nil)
    cg.addPath(rounded)
    cg.setFillColor(paper.cgColor)
    cg.fillPath()

    // Optical compensation keeps the thin rule legible in menu/Finder sizes.
    cg.setLineWidth(pixels <= 32 ? 4.5 : 3.1)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(ink.cgColor)

    cg.move(to: CGPoint(x: 32.8, y: 26.3)); cg.addLine(to: CGPoint(x: 32.8, y: 69.7))
    cg.move(to: CGPoint(x: 44.2, y: 34.7)); cg.addLine(to: CGPoint(x: 64.7, y: 34.7))
    cg.move(to: CGPoint(x: 44.2, y: 48)); cg.addLine(to: CGPoint(x: 64.7, y: 48))
    cg.move(to: CGPoint(x: 44.2, y: 61.3)); cg.addLine(to: CGPoint(x: 57.2, y: 61.3))
    cg.strokePath()

    // Where you are on the margin — the one accent, sitting on the rule line.
    cg.setFillColor(amber.cgColor)
    cg.fillEllipse(in: CGRect(x: 27.15, y: 42.35, width: 11.3, height: 11.3))
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
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Modern ICNS representations accept PNG payloads, including Retina sizes.
// Writing the container directly avoids iconutil's system conversion service,
// which is unavailable in some restricted macOS build environments.
let variants: [(name: String, pixels: Int, element: String)] = [
    ("icon_16x16", 16, "icp4"), ("icon_16x16@2x", 32, "ic11"),
    ("icon_32x32", 32, "icp5"), ("icon_32x32@2x", 64, "ic12"),
    ("icon_128x128", 128, "ic07"), ("icon_128x128@2x", 256, "ic13"),
    ("icon_256x256", 256, "ic08"), ("icon_256x256@2x", 512, "ic14"),
    ("icon_512x512", 512, "ic09"), ("icon_512x512@2x", 1024, "ic10"),
]

func bigEndianLength(_ length: Int) -> Data {
    var value = UInt32(length).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var elements = Data()

for variant in variants {
    guard let png = render(variant.pixels) else {
        FileHandle.standardError.write("failed to render \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try png.write(to: iconset.appendingPathComponent("\(variant.name).png"))
    elements.append(Data(variant.element.utf8))
    elements.append(bigEndianLength(png.count + 8))
    elements.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianLength(elements.count + 8))
icns.append(elements)
let destination = root.appendingPathComponent("build/Foglio.icns")
try icns.write(to: destination)
// Require native decoding before the bundle picks up the generated resource.
guard let decoded = NSImage(contentsOf: destination), decoded.isValid else {
    throw NSError(domain: "Foglio.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS could not decode the generated ICNS."])
}
print("wrote \(variants.count) sizes and \(destination.path)")
