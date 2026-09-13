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
            // `ok` is not just a checkbox fill — it letters COMPLETED TODAY at
            // 11pt (TasksView.swift:592), so it has to carry small text.
            Check.expect(
                contrast(t.ok, t.surface) >= 4.5,
                "\(mode.label) done-colour carries a heading (\(ratio(t.ok, t.surface)))"
            )
            // Slate Amber's own clay sits at 3.75, so that is the floor.
            Check.expect(
                contrast(t.clay, t.surface) >= 3.7,
                "\(mode.label) warning ink stays legible (\(ratio(t.clay, t.surface)))"
            )
        }
    }

    Check.suite("Themes — semantic colours belong to their palette") {
        for mode in ThemeMode.allCases {
            let t = mode.theme

            // On a dark ground a saturated hue that answers to nothing else on
            // screen reads as a foreign colour — a mint COMPLETED TODAY in a
            // navy room. Night Moss avoided that by making done-ness its own
            // accent; every dark palette now follows it.
            if t.isDark {
                Check.expect(
                    t.ok == t.accent,
                    "\(mode.label) takes its done-colour from its accent"
                )
            } else {
                // The light palettes use the complement instead, but only as
                // dark low-chroma ink, which is why it doesn't shout.
                Check.expect(
                    brightness(t.ok) < 0.55 && saturation(t.ok) < 0.6,
                    "\(mode.label) done-colour stays tinted ink, not a colour"
                )
            }

            // Warnings are warm in every palette, original two included.
            Check.expect(
                (10...45).contains(hueDegrees(t.clay)),
                "\(mode.label) warning ink is warm (\(hueDegrees(t.clay))°)"
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
        Check.equal(Theme.dark.ok, Color(hex: 0x8FB98A), "dark done-colour is still the moss")
        Check.equal(Theme.light.ok, Color(hex: 0x3E7C74), "light done-colour is still the teal")
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

/// Contrast of `fg` painted on `bg`.
///
/// `fg` is composited first: several tokens are translucent — the light
/// palettes' `invMuted` is the ground at 60% over the ink — and reading their
/// components raw would score a colour that never reaches the screen.
private func contrast(_ fg: Color, _ bg: Color) -> Double {
    let (l1, l2) = (luminance(composite(fg, over: bg)), luminance(bg))
    let (hi, lo) = l1 > l2 ? (l1, l2) : (l2, l1)
    return (hi + 0.05) / (lo + 0.05)
}

private func composite(_ fg: Color, over bg: Color) -> Color {
    guard let f = NSColor(fg).usingColorSpace(.sRGB),
          let b = NSColor(bg).usingColorSpace(.sRGB) else { return fg }
    let a = f.alphaComponent
    guard a < 1 else { return fg }
    return Color(
        .sRGB,
        red: Double(f.redComponent * a + b.redComponent * (1 - a)),
        green: Double(f.greenComponent * a + b.greenComponent * (1 - a)),
        blue: Double(f.blueComponent * a + b.blueComponent * (1 - a)),
        opacity: 1
    )
}

private func ratio(_ a: Color, _ b: Color) -> String {
    String(format: "%.1f:1", contrast(a, b))
}

/// Hue in degrees, and the two HSB components used to tell tinted ink from a
/// colour that shouts.
private func hueDegrees(_ color: Color) -> Int {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
    return Int((rgb.hueComponent * 360).rounded())
}

private func saturation(_ color: Color) -> Double {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
    return Double(rgb.saturationComponent)
}

private func brightness(_ color: Color) -> Double {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
    return Double(rgb.brightnessComponent)
}

/// Every foreground/background pair the app actually paints text in, held to
/// the standard the design's own two palettes set.
///
/// The bar is relative rather than a flat WCAG number on purpose: Slate Amber
/// letters an active rail icon at 3.35:1 and a muted field at 3.43:1, and this
/// suite is not the place to relitigate the shipped design. What it does catch
/// is a new palette being *worse* than that anywhere — which is how Midnight
/// shipped a mint COMPLETED TODAY in a navy room.
func themeSurfaceTests() {
    // Each pair is (what it is, ink, ground). Sources are the call sites.
    let pairs: [(String, KeyPath<Theme, Color>, KeyPath<Theme, Color>)] = [
        ("body text on the ground", \.text, \.bg),
        ("text on a card", \.text, \.surface),
        ("text on a raised card", \.text, \.raised),
        ("muted meta on a card", \.muted, \.surface),
        ("muted text in a field", \.muted, \.field),
        ("muted on a raised card", \.muted, \.raised),
        // BarView.swift:79, MainWindowView.swift:151
        ("an active rail icon", \.accentDeep, \.bg),
        // NoteEditor.swift:212, CalendarView.swift:178
        ("an accented link or meta", \.accentDeep, \.surface),
        ("a button label", \.onAccent, \.accent),
        // TasksView.swift:592
        ("COMPLETED TODAY", \.ok, \.surface),
        // TasksView.swift:551 — the tick inside a checked box
        ("a task's tick", \.bg, \.ok),
        // TrashView.swift:92, MeetingAlertView.swift:19
        ("warning ink", \.clay, \.surface),
        // BarView.swift:90 — the meeting count on its capsule
        ("the bar's meeting badge", \.raised, \.clay),
        // NotesView.swift:502
        ("the notes selection tick", \.surface, \.accentDeep),
        // SettingsView.swift:353-367 — the inverted Shortcuts card
        ("the shortcuts card", \.invText, \.invBg),
        ("the shortcuts card's muted rows", \.invMuted, \.invBg),
        // BlockView.swift:221 — syntax in a code block
        ("a code comment", \.muted, \.codeBg),
        ("a code string", \.ok, \.codeBg),
        ("a code number", \.clay, \.codeBg),
        ("a code keyword", \.accentDeep, \.codeBg),
        ("code identifiers", \.text, \.codeBg),
    ]

    Check.suite("Themes — every surface the app paints text on") {
        for (what, ink, ground) in pairs {
            // What the design itself settles for in this spot.
            let floor = min(
                contrast(Theme.light[keyPath: ink], Theme.light[keyPath: ground]),
                contrast(Theme.dark[keyPath: ink], Theme.dark[keyPath: ground])
            )
            let worst = ThemeMode.allCases.min {
                contrast($0.theme[keyPath: ink], $0.theme[keyPath: ground])
                    < contrast($1.theme[keyPath: ink], $1.theme[keyPath: ground])
            }!
            let got = contrast(worst.theme[keyPath: ink], worst.theme[keyPath: ground])

            // Clear WCAG AA, or — where the design itself doesn't — at least
            // don't fall below what it settles for. A palette is not required
            // to beat pure-white-on-near-black in absolute terms: Paper's
            // cream ground reads at 13:1 rather than 15:1 and is perfectly
            // legible. What it may not do is get worse in the thin spots.
            let bar = min(floor, 4.5)
            Check.expect(
                got >= bar - 0.1,
                "\(what): weakest is \(worst.label) at \(String(format: "%.2f", got)):1 "
                    + "(needs \(String(format: "%.2f", bar)):1, design sets \(String(format: "%.2f", floor)):1)"
            )
        }
    }
}
