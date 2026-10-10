import AppKit

// Exploratory artwork only. Does not replace the shipped app icon.
let width = 1440, height = 560
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let cg = context.cgContext
cg.translateBy(x: 0, y: CGFloat(height))
cg.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let ivory = color(0xF3EBDD), amber = color(0xDEA958), ink = color(0x29251F)
func rounded(_ rect: CGRect, _ radius: CGFloat, _ fill: NSColor) {
    cg.setFillColor(fill.cgColor)
    cg.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.fillPath()
}
func polygon(_ points: [CGPoint], _ fill: NSColor) {
    cg.beginPath(); cg.move(to: points[0])
    for point in points.dropFirst() { cg.addLine(to: point) }
    cg.closePath(); cg.setFillColor(fill.cgColor); cg.fillPath()
}
func text(_ value: String, _ rect: CGRect, size: CGFloat, fill: NSColor, weight: NSFont.Weight = .regular) {
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: fill])
}
func plate(_ fill: NSColor) {
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 8), blur: 15, color: color(0x000000).withAlphaComponent(0.25).cgColor)
    rounded(CGRect(x: 0, y: 0, width: 240, height: 240), 54, fill)
    cg.restoreGState()
}
func drawConcept(_ index: Int) {
    switch index {
    case 0:
        plate(ivory)
        // The silhouette reads as F; the amber triangular fold supplies a paper cue.
        polygon([CGPoint(x: 72,y: 54), CGPoint(x: 178,y: 54), CGPoint(x: 178,y: 92),
                 CGPoint(x: 113,y: 92), CGPoint(x: 113,y: 114), CGPoint(x: 159,y: 114),
                 CGPoint(x: 159,y: 148), CGPoint(x: 113,y: 148), CGPoint(x: 113,y: 187),
                 CGPoint(x: 72,y: 187)], ink)
        polygon([CGPoint(x: 140,y: 54), CGPoint(x: 178,y: 54), CGPoint(x: 178,y: 92)], amber)
        polygon([CGPoint(x: 140,y: 54), CGPoint(x: 140,y: 92), CGPoint(x: 178,y: 92)], color(0xBC833D))
    case 1:
        plate(ink)
        cg.saveGState()
        cg.translateBy(x: 120, y: 125); cg.rotate(by: -0.13)
        rounded(CGRect(x: -66, y: -74, width: 116, height: 148), 17, color(0xB5874B))
        cg.restoreGState()
        cg.saveGState()
        cg.translateBy(x: 128, y: 118); cg.rotate(by: 0.07)
        rounded(CGRect(x: -58, y: -75, width: 116, height: 148), 17, ivory)
        rounded(CGRect(x: -28, y: -41, width: 60, height: 7), 3.5, color(0xBFB3A0))
        rounded(CGRect(x: -28, y: -19, width: 45, height: 7), 3.5, color(0xBFB3A0))
        polygon([CGPoint(x: 21,y: -75), CGPoint(x: 39,y: -75), CGPoint(x: 39,y: -19), CGPoint(x: 30,y: -27), CGPoint(x: 21,y: -19)], amber)
        cg.restoreGState()
    case 2:
        plate(ink)
        // Rounded, geometric F with an accent detached from the crossbar.
        rounded(CGRect(x: 66, y: 52, width: 38, height: 139), 18, ivory)
        rounded(CGRect(x: 84, y: 52, width: 94, height: 36), 18, ivory)
        rounded(CGRect(x: 84, y: 110, width: 48, height: 32), 16, ivory)
        cg.setFillColor(amber.cgColor); cg.fillEllipse(in: CGRect(x: 144, y: 110, width: 32, height: 32))
    default:
        plate(ivory)
        rounded(CGRect(x: 71, y: 52, width: 9, height: 136), 4.5, ink)
        rounded(CGRect(x: 104, y: 76, width: 70, height: 10), 5, ink)
        rounded(CGRect(x: 104, y: 115, width: 70, height: 10), 5, ink)
        rounded(CGRect(x: 104, y: 154, width: 48, height: 10), 5, ink)
        cg.setFillColor(amber.cgColor); cg.fillEllipse(in: CGRect(x: 59, y: 104, width: 33, height: 33))
    }
}
cg.setFillColor(color(0x171715).cgColor); cg.fill(CGRect(x: 0,y: 0,width: width,height: height))
text("FOGLIO / ICON DIRECTIONS", CGRect(x: 52,y: 30,width: 900,height: 35), size: 23, fill: ivory, weight: .semibold)
text("Ivory paper. Charcoal ink. One warm accent.", CGRect(x: 52,y: 72,width: 1000,height: 28), size: 16, fill: color(0xA7A394))
let names = ["01  Folded F", "02  Layered pages", "03  Studio monogram", "04  Refined margin"]
let descriptions = ["A distinctive mark with a paper fold.", "Tactile, familiar, and welcoming.", "Bold and clear at small sizes.", "A warmer evolution of today's icon."]
for index in 0..<4 {
    let x = CGFloat(52 + index * 348)
    cg.saveGState(); cg.translateBy(x: x + 27, y: 145); drawConcept(index); cg.restoreGState()
    text(names[index], CGRect(x: x,y: 420,width: 330,height: 30), size: 20, fill: ivory, weight: .medium)
    text(descriptions[index], CGRect(x: x,y: 455,width: 330,height: 28), size: 14, fill: color(0xA7A394))
    // Dock-scale check alongside the large preview.
    cg.saveGState(); cg.translateBy(x: x + 28, y: 495); cg.scaleBy(x: 32 / 240, y: 32 / 240); drawConcept(index); cg.restoreGState()
    text("32 px", CGRect(x: x + 72,y: 501,width: 140,height: 25), size: 12, fill: color(0xA7A394))
}
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("design/icon-concepts/comparison.png")
try rep.representation(using: .png, properties: [:])!.write(to: output)
print(output.path)
