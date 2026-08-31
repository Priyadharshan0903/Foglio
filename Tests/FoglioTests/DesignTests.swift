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
