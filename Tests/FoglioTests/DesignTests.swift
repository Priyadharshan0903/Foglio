import Foundation
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
        Check.equal(Section.railItems.count, 7, "rail shows seven items")
        Check.expect(
            Section.barItems.allSatisfy(Section.railItems.contains),
            "rail is a superset of the bar"
        )
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
