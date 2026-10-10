import AppKit

/// Draw Notes-style circles in place of the editor's semantic checklist
/// markers. The characters remain in text storage for editing, undo, and
/// Markdown export; ordinary square symbols in prose or code stay untouched.
final class NoteChecklistLayoutManager: NSLayoutManager {
    var accent: NSColor = .controlAccentColor
    var checkmarkInk: NSColor = .textBackgroundColor
    var outline: NSColor = .secondaryLabelColor

    struct Marker {
        let index: Int
        let glyph: Int
        let rect: NSRect
        let checked: Bool
    }

    func markers(in glyphRange: NSRange) -> [Marker] {
        guard glyphRange.length > 0, let storage = textStorage else { return [] }
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let ns = storage.string as NSString
        var offset = ns.lineRange(for: NSRange(location: characters.location, length: 0)).location
        var result: [Marker] = []
        while offset < min(characters.upperBound, storage.length) {
            let range = ns.lineRange(for: NSRange(location: offset, length: 0))
            defer { offset = range.upperBound }
            guard storage.attribute(.noteStyle, at: offset, effectiveRange: nil) as? String == NoteStyle.checklist.rawValue,
                  NoteDocument.prefixMatch("^[☐☑][ \\t]", in: ns.substring(with: range)) != nil else { continue }
            let glyph = glyphIndexForCharacter(at: offset)
            guard NSLocationInRange(glyph, glyphRange) else { continue }
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let position = location(forGlyphAt: glyph)
            let font = storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 14)
            let rect = NSRect(x: line.minX + position.x,
                              y: line.minY + position.y - font.capHeight / 2 - 9,
                              width: 18, height: 18)
            result.append(Marker(index: offset, glyph: glyph, rect: rect,
                                 checked: ns.substring(with: NSRange(location: offset, length: 1)) == "☑"))
        }
        return result
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let circles = markers(in: glyphsToShow)
        var dividers: [(Int, NSRect)] = []
        if let storage = textStorage {
            enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, _, range, _ in
                let index = self.characterIndexForGlyph(at: range.location)
                if storage.attribute(.noteStyle, at: index, effectiveRange: nil) as? String == NoteStyle.divider.rawValue {
                    dividers.append((range.location, rect))
                }
            }
        }
        var start = glyphsToShow.location
        for glyph in (circles.map(\.glyph) + dividers.map(\.0)).sorted() {
            if glyph > start {
                super.drawGlyphs(forGlyphRange: NSRange(location: start, length: glyph - start), at: origin)
            }
            start = glyph + 1
        }
        for (_, rect) in dividers {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: origin.x + rect.minX, y: origin.y + rect.midY))
            line.line(to: NSPoint(x: origin.x + rect.maxX, y: origin.y + rect.midY))
            line.lineWidth = 1
            outline.withAlphaComponent(0.3).setStroke()
            line.stroke()
        }
        if start < glyphsToShow.upperBound {
            super.drawGlyphs(forGlyphRange: NSRange(location: start, length: glyphsToShow.upperBound - start), at: origin)
        }
        for marker in circles {
            let rect = marker.rect.offsetBy(dx: origin.x, dy: origin.y)
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
            if marker.checked {
                accent.setFill()
                circle.fill()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: rect.minX + 5, y: rect.minY + 9))
                tick.line(to: NSPoint(x: rect.minX + 8, y: rect.minY + 12))
                tick.line(to: NSPoint(x: rect.minX + 13, y: rect.minY + 6))
                tick.lineWidth = 1.7
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                checkmarkInk.setStroke()
                tick.stroke()
            } else {
                outline.withAlphaComponent(0.65).setStroke()
                circle.lineWidth = 1.5
                circle.stroke()
            }
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage {
            enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, _, range, _ in
                let index = self.characterIndexForGlyph(at: range.location)
                let style = storage.attribute(.noteStyle, at: index, effectiveRange: nil) as? String
                let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor ?? .labelColor
                if style == NoteStyle.codeBlock.rawValue {
                    color.withAlphaComponent(0.06).setFill()
                    rect.offsetBy(dx: origin.x, dy: origin.y).fill()
                } else if style == NoteStyle.quote.rawValue {
                    self.outline.withAlphaComponent(0.5).setFill()
                    NSRect(x: origin.x + 4, y: origin.y + rect.minY, width: 2, height: rect.height).fill()
                }
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    func checklistIndex(at point: NSPoint, in container: NSTextContainer) -> Int? {
        // Restrict work to the line around the pointer, including its margin.
        let glyph = glyphIndex(for: point, in: container)
        guard glyph < numberOfGlyphs else { return nil }
        var lineRange = NSRange()
        _ = lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
        return markers(in: lineRange).first {
            $0.rect.insetBy(dx: -3, dy: -3).contains(point)
        }?.index
    }
}
