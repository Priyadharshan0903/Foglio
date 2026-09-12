import Foundation
import SwiftUI
import AppKit
@testable import FoglioCore

func designTokenTests() {
    Check.suite("Design tokens") {
        Check.expect(Theme.light.isDark == false, "light theme is not dark")
        Check.expect(Theme.dark.isDark == true, "dark theme is dark")
        // The accent deliberately changes hue between themes (amber -> moss).
        Check.expect(Theme.light.accent != Theme.dark.accent, "accent differs across themes")
    }

    Check.suite("Icons") {
        for icon in Icon.allCases {
            Check.expect(!icon.path(scaledTo: 17).isEmpty, "\(icon.rawValue) renders a path")
        }
    }

    Check.suite("Navigation") {
        Check.equal(Section.barItems.count, 5, "bar shows five items")
        Check.equal(Section.railItems.count, 8, "rail shows eight items")
        Check.expect(
            Section.barItems.allSatisfy(Section.railItems.contains),
            "rail is a superset of the bar"
        )
        // Trash is somewhere you go to undo something, not somewhere you work,
        // so it stays off the floating bar and sits last on the rail.
        Check.expect(!Section.barItems.contains(.trash), "trash is not on the bar")
        Check.equal(Section.railItems.last, .trash, "and sits at the end of the rail")
    }
}

/// The docking rule, extracted so the geometry can be checked without a screen.
func dockingTests() {
    // A typical laptop display's visible area.
    let visible = CGRect(x: 0, y: 94, width: 1728, height: 990)

    // Calls the shipping rule, not a copy of it.
    func edge(droppedAt center: CGPoint) -> BarEdge {
        BarEdge.docking(for: center, in: visible)
    }

    Check.suite("Bar docking — where a drop lands") {
        // The reported bug: dropped mid-screen it flew to the top, because a
        // screen is far wider than tall so "top" wins a naive nearest-edge test.
        let middle = CGPoint(x: visible.midX - 20, y: visible.midY)
        Check.equal(edge(droppedAt: middle), .left, "a centre drop picks a side, not the top")

        Check.equal(
            edge(droppedAt: CGPoint(x: 200, y: visible.midY)), .left,
            "left half docks left"
        )
        Check.equal(
            edge(droppedAt: CGPoint(x: 1500, y: visible.midY)), .right,
            "right half docks right"
        )
        Check.equal(
            edge(droppedAt: CGPoint(x: visible.midX + 20, y: visible.midY)), .right,
            "just right of centre docks right"
        )
    }

    Check.suite("Bar docking — the top band") {
        // Near the top it should still go horizontal, from either side.
        Check.equal(
            edge(droppedAt: CGPoint(x: 300, y: visible.maxY - 30)), .top,
            "dropped near the top docks top"
        )
        Check.equal(
            edge(droppedAt: CGPoint(x: 1400, y: visible.maxY - 30)), .top,
            "from the right side too"
        )
        // But only near the top — the band must not swallow the upper third.
        Check.equal(
            edge(droppedAt: CGPoint(x: 300, y: visible.maxY - 300)), .left,
            "well below the top band stays a side dock"
        )
        Check.expect(BarEdge.top.isHorizontal, "the top dock is the horizontal one")
        Check.expect(!BarEdge.left.isHorizontal && !BarEdge.right.isHorizontal,
                     "side docks stay vertical")
    }
}

func iconAlignmentTests() {
    Check.suite("Icons — optically centred") {
        // Stacked in a 34pt column, an icon a point off-centre is visible as a
        // wobble. Every glyph's bounding box should sit centred in its box.
        for icon in Icon.allCases {
            let box = icon.path(scaledTo: 24).boundingRect
            let offsetX = abs(box.midX - 12)
            let offsetY = abs(box.midY - 12)
            Check.expect(
                offsetX < 0.01 && offsetY < 0.01,
                "\(icon.rawValue) is centred (off by \(String(format: "%.2f", offsetX)), \(String(format: "%.2f", offsetY)))"
            )
        }
    }

    Check.suite("Icons — scale cleanly") {
        // Centring must not change how big a glyph is, only where it sits.
        for icon in Icon.allCases {
            let small = icon.path(scaledTo: 12).boundingRect
            let large = icon.path(scaledTo: 24).boundingRect
            let ratio = large.width > 0 ? small.width / large.width : 0.5
            Check.expect(
                abs(ratio - 0.5) < 0.01,
                "\(icon.rawValue) halves cleanly at half the size"
            )
        }
    }
}

/// Every palette in the picker, checked for the things a palette can quietly
/// get wrong: ink you can't read on its own ground, a button label lost in its
/// accent, or a preference name that stops resolving.
func themeTests() {
    Check.suite("Themes — the list") {
        Check.equal(ThemeMode.allCases.count, 8, "eight palettes ship")
        Check.equal(
            ThemeMode.lightModes.count + ThemeMode.darkModes.count,
            ThemeMode.allCases.count,
            "every palette is either light or dark"
        )
        Check.equal(ThemeMode.lightModes.count, 4, "four of them are light")

        // The raw values are the on-disk preference: someone who picked dark
        // before this list grew must still land on dark.
        Check.equal(ThemeMode(rawValue: "light"), .light, "an old light preference still resolves")
        Check.equal(ThemeMode(rawValue: "dark"), .dark, "and an old dark one")
        Check.equal(
            Set(ThemeMode.allCases.map(\.rawValue)).count, ThemeMode.allCases.count,
            "preference names are unique"
        )

        let duplicates = ThemeMode.allCases.filter { mode in
            ThemeMode.allCases.contains { $0 != mode && $0.theme == mode.theme }
        }
        Check.expect(duplicates.isEmpty, "no two palettes are the same colours")
    }

    Check.suite("Themes — legibility") {
        for mode in ThemeMode.allCases {
            let t = mode.theme

            // A dark theme must actually be darker than its own ink, or the
            // window ends up in the wrong system appearance.
            Check.expect(
                t.isDark == (luminance(t.bg) < luminance(t.text)),
                "\(mode.label) is honest about being \(t.isDark ? "dark" : "light")"
            )

            // Body text: WCAG AAA, which every palette here clears comfortably.
            Check.expect(
                contrast(t.text, t.bg) >= 7,
                "\(mode.label) text reads on the ground (\(ratio(t.text, t.bg)))"
            )
            Check.expect(
                contrast(t.text, t.surface) >= 7,
                "\(mode.label) text reads on a card (\(ratio(t.text, t.surface)))"
            )
            // Secondary ink only has to clear the non-text / large-text bar —
            // Slate Amber's own muted grey sits at 3.3, so that is the floor.
            Check.expect(
                contrast(t.muted, t.surface) >= 3,
                "\(mode.label) muted ink stays visible (\(ratio(t.muted, t.surface)))"
            )
            // Accent-filled buttons carry 11.5pt labels.
            Check.expect(
                contrast(t.onAccent, t.accent) >= 4.5,
                "\(mode.label) button labels read on the accent (\(ratio(t.onAccent, t.accent)))"
            )
        }
    }

    Check.suite("Themes — the two from the design survive the rewrite") {
        // `Theme.make` derives the hairlines, wash and inverted card that used
        // to be spelled out. These are the values from `Day Log.dc.html`:15-30.
        Check.equal(Theme.light.line, Color(hex: 0x1A1E22, alpha: 0.09), "light hairline")
        Check.equal(Theme.light.lineSoft, Color(hex: 0x1A1E22, alpha: 0.06), "light soft hairline")
        Check.equal(Theme.light.accentSoft, Color(hex: 0xE09A2B, alpha: 0.16), "light accent wash")
        Check.equal(Theme.light.invBg, Color(hex: 0x1A1E22), "light inverted card ground")
        Check.equal(Theme.light.invText, Color(hex: 0xF1F2F3), "light inverted card ink")
        Check.equal(Theme.dark.line, Color(hex: 0xE8E9E6, alpha: 0.10), "dark hairline")
        Check.equal(Theme.dark.invMuted, Color(hex: 0x5B615E), "dark inverted card muted ink")
        Check.equal(
            Theme.dark.shadowWin,
            ShadowSpec(color: .black.opacity(0.65), radius: 38, y: 32),
            "dark window shadow"
        )
    }
}

/// sRGB relative luminance (WCAG 2.1).
private func luminance(_ color: Color) -> Double {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
    func channel(_ raw: CGFloat) -> Double {
        let v = Double(raw)
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(rgb.redComponent)
        + 0.7152 * channel(rgb.greenComponent)
        + 0.0722 * channel(rgb.blueComponent)
}

private func contrast(_ a: Color, _ b: Color) -> Double {
    let (l1, l2) = (luminance(a), luminance(b))
    let (hi, lo) = l1 > l2 ? (l1, l2) : (l2, l1)
    return (hi + 0.05) / (lo + 0.05)
}

private func ratio(_ a: Color, _ b: Color) -> String {
    String(format: "%.1f:1", contrast(a, b))
}
