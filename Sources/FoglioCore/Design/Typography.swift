import SwiftUI
import AppKit
import CoreText

/// The design is set in Geist / Geist Mono (Day Log.dc.html:12).
///
/// Google Fonts ships Geist only as **variable** fonts — one file per family
/// carrying a `wght` axis, with no static `Geist-Medium.ttf` to ask for by name.
/// So `Font.custom("Geist-SemiBold", …)` would silently fall back to the system
/// face. Instead each weight is built as an instance of the variable font, and
/// the family names are read out of the files at registration rather than
/// guessed at.
///
/// If the files are missing the whole thing degrades to the system face, so the
/// app still builds and runs without them.
enum Typo {
    private static var sansFamily: String?
    private static var monoFamily: String?

    /// The OpenType `wght` axis, four-char code 'wght'.
    private static let weightAxis = 0x77676874 as CFNumber

    static var geistAvailable: Bool { sansFamily != nil }

    static func registerBundledFonts() {
        sansFamily = register("Geist")
        monoFamily = register("GeistMono")
    }

    /// Registers one font file and returns the family name it declares.
    private static func register(_ resource: String) -> String? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "ttf") else {
            return nil
        }

        // Already-registered is fine — this can run twice in a debug relaunch.
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let code = CFErrorGetCode(error?.takeUnretainedValue())
            let alreadyRegistered = code == CTFontManagerError.alreadyRegistered.rawValue
            if !alreadyRegistered { return nil }
        }

        guard
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            let first = descriptors.first,
            let family = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String
        else { return nil }

        return family
    }

    /// What the loader actually resolved — used to confirm the bundled faces are
    /// in use rather than a silent system fallback.
    static func describeResolved() -> String {
        let names = [sansFamily ?? "nil", monoFamily ?? "nil"]
        let weights: [CGFloat] = [400, 500, 600]
        let postscript = sansFamily.map { family in
            weights.map { w -> String in
                let d = CTFontDescriptorCreateWithAttributes([
                    kCTFontFamilyNameAttribute: family,
                    kCTFontVariationAttribute: [weightAxis: w as CFNumber] as CFDictionary,
                ] as CFDictionary)
                let f = CTFontCreateWithFontDescriptor(d, 13, nil)
                let traits = CTFontCopyTraits(f) as? [CFString: Any]
                let value = traits?[kCTFontWeightTrait] as? Double ?? .nan
                return "\(Int(w)):\(String(format: "%.2f", value))"
            }.joined(separator: " ")
        } ?? "—"
        return "families=\(names) wghtTrait=[\(postscript)]"
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let sansFamily,
              let font = instance(of: sansFamily, size: size, weight: axisValue(weight))
        else { return .system(size: size, weight: weight) }
        return font
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let monoFamily,
              let font = instance(of: monoFamily, size: size, weight: axisValue(weight))
        else { return .system(size: size, weight: weight, design: .monospaced) }
        return font
    }

    /// Builds a concrete instance of a variable font at a given weight.
    private static func instance(of family: String, size: CGFloat, weight: CGFloat) -> Font? {
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: [weightAxis: weight as CFNumber] as CFDictionary,
        ] as CFDictionary)

        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return Font(ctFont)
    }

    /// The design only ever uses 400/500/600 (`Geist:wght@400;500;600`).
    private static func axisValue(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .bold, .heavy, .black: 700
        case .semibold: 600
        case .medium: 500
        case .light, .thin, .ultraLight: 300
        default: 400
        }
    }
}
