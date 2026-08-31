import SwiftUI
import AppKit
import CoreText

/// The design is set in Geist / Geist Mono. Those aren't system fonts, so they
/// get registered from the app bundle at launch. Until the TTFs are dropped into
/// `Sources/Foglio/Resources/Fonts/`, every call falls back to the system face,
/// so the app builds and runs correctly either way — only the metrics differ.
enum Typo {
    private(set) static var geistAvailable = false

    static func registerBundledFonts() {
        let names = [
            "Geist-Regular", "Geist-Medium", "Geist-SemiBold",
            "GeistMono-Regular", "GeistMono-Medium",
        ]
        var registered = 0
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
                registered += 1
            }
        }
        geistAvailable = registered == names.count
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard geistAvailable else { return .system(size: size, weight: weight) }
        switch weight {
        case .semibold, .bold: return .custom("Geist-SemiBold", size: size)
        case .medium: return .custom("Geist-Medium", size: size)
        default: return .custom("Geist-Regular", size: size)
        }
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard geistAvailable else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(weight == .regular ? "GeistMono-Regular" : "GeistMono-Medium", size: size)
    }
}
