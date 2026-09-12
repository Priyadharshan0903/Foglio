import SwiftUI

// Design tokens. `light` and `dark` are transcribed verbatim from
// `Day Log.dc.html` lines 15-30 — the "Slate Amber" and "Night Moss" palettes,
// whose accent deliberately changes hue between them (amber -> moss). The rest
// are extra palettes in the same shape; see `ThemeMode` for the pickable list.

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct ShadowSpec: Equatable {
    var color: Color
    var radius: CGFloat
    var y: CGFloat
}

struct Theme: Equatable {
    var isDark: Bool

    // Surfaces
    var desk: Color
    var bg: Color
    var surface: Color
    var raised: Color
    var field: Color
    var codeBg: Color

    // Ink
    var text: Color
    var muted: Color
    var line: Color
    var lineSoft: Color

    // Accent
    var accent: Color
    var onAccent: Color
    var accentDeep: Color
    var accentSoft: Color

    // Semantic
    var ok: Color
    var clay: Color

    // Inverted surface (the Shortcuts card)
    var invBg: Color
    var invText: Color
    var invMuted: Color

    var shadowFloat: ShadowSpec
    var shadowWin: ShadowSpec
}

extension Theme {
    /// Builds a palette from only the colours that actually differ between
    /// themes.
    ///
    /// Hairlines, the accent wash, the inverted card and both shadows follow
    /// the same formula in every palette — they are the ink and the ground at
    /// fixed opacities — so deriving them keeps a new theme to the dozen
    /// colours worth choosing, and stops one of the twenty being forgotten.
    /// The two original palettes come out of it byte-identical to the design.
    static func make(
        isDark: Bool,
        desk: UInt32,
        bg: UInt32,
        surface: UInt32,
        raised: UInt32,
        field: UInt32,
        codeBg: UInt32,
        text: UInt32,
        muted: UInt32,
        accent: UInt32,
        onAccent: UInt32,
        accentDeep: UInt32,
        ok: UInt32,
        clay: UInt32,
        invMuted: UInt32? = nil
    ) -> Theme {
        let ink = Color(hex: text)
        return Theme(
            isDark: isDark,
            desk: Color(hex: desk),
            bg: Color(hex: bg),
            surface: Color(hex: surface),
            raised: Color(hex: raised),
            field: Color(hex: field),
            codeBg: Color(hex: codeBg),
            text: ink,
            muted: Color(hex: muted),
            line: Color(hex: text, alpha: isDark ? 0.10 : 0.09),
            lineSoft: Color(hex: text, alpha: isDark ? 0.07 : 0.06),
            accent: Color(hex: accent),
            onAccent: Color(hex: onAccent),
            accentDeep: Color(hex: accentDeep),
            accentSoft: Color(hex: accent, alpha: 0.16),
            ok: Color(hex: ok),
            clay: Color(hex: clay),
            // The inverted card is the palette turned over: the ink becomes the
            // ground and the ground becomes the ink.
            invBg: ink,
            invText: Color(hex: bg),
            invMuted: invMuted.map { Color(hex: $0) } ?? Color(hex: bg, alpha: 0.6),
            shadowFloat: isDark
                ? ShadowSpec(color: .black.opacity(0.6), radius: 20, y: 16)
                : ShadowSpec(color: Color(hex: text, alpha: 0.22), radius: 18, y: 14),
            shadowWin: isDark
                ? ShadowSpec(color: .black.opacity(0.65), radius: 38, y: 32)
                : ShadowSpec(color: Color(hex: text, alpha: 0.28), radius: 35, y: 30)
        )
    }

    // MARK: - Light palettes

    /// Slate Amber — the original daytime palette (`Day Log.dc.html`:15).
    static let light = Theme.make(
        isDark: false,
        desk: 0xDEE1E3, bg: 0xF1F2F3, surface: 0xFFFFFF, raised: 0xFFFFFF,
        field: 0xF4F5F6, codeBg: 0xF4F5F6,
        text: 0x1A1E22, muted: 0x7C858E,
        accent: 0xE09A2B, onAccent: 0x1A1E22, accentDeep: 0xB87514,
        ok: 0x3E7C74, clay: 0xB87514
    )

    /// Paper — warm cream stock and sepia ink, for people who want the app to
    /// look like the notebook it replaced.
    static let paper = Theme.make(
        isDark: false,
        desk: 0xDBD3C3, bg: 0xF3EDE1, surface: 0xFBF7EF, raised: 0xFFFDF8,
        field: 0xEFE8DA, codeBg: 0xEDE5D5,
        text: 0x2A2520, muted: 0x8A8071,
        accent: 0xB05423, onAccent: 0xFBF7EF, accentDeep: 0x8C3F18,
        ok: 0x5E7A4F, clay: 0xA8763C
    )

    /// Harbor — cool blue-grey with a deep teal accent.
    static let harbor = Theme.make(
        isDark: false,
        desk: 0xCFD8DE, bg: 0xE9EEF2, surface: 0xFFFFFF, raised: 0xFFFFFF,
        field: 0xEDF1F4, codeBg: 0xE6ECF0,
        text: 0x17242E, muted: 0x6B7E8B,
        accent: 0x2E7D8F, onAccent: 0xFFFFFF, accentDeep: 0x1C5D6C,
        ok: 0x3E7C74, clay: 0xB5643C
    )

    /// Blossom — a soft warm white carrying a plum accent.
    static let blossom = Theme.make(
        isDark: false,
        desk: 0xE4DCE0, bg: 0xF6F1F3, surface: 0xFFFFFF, raised: 0xFFFFFF,
        field: 0xF5EFF2, codeBg: 0xF2EAEE,
        text: 0x241B21, muted: 0x8A7A83,
        accent: 0xA8446B, onAccent: 0xFFFFFF, accentDeep: 0x82304F,
        ok: 0x4E7A63, clay: 0xB26A4A
    )

    // MARK: - Dark palettes

    /// Night Moss — the original after-hours palette (`Day Log.dc.html`:23).
    static let dark = Theme.make(
        isDark: true,
        desk: 0x0A0C0D, bg: 0x14171A, surface: 0x1B1F22, raised: 0x23282B,
        field: 0x14171A, codeBg: 0x101314,
        text: 0xE8E9E6, muted: 0x8A928F,
        accent: 0x8FB98A, onAccent: 0x14171A, accentDeep: 0xA6CBA1,
        ok: 0x8FB98A, clay: 0xD08A64,
        invMuted: 0x5B615E
    )

    /// Midnight — deep navy with a periwinkle accent.
    static let midnight = Theme.make(
        isDark: true,
        desk: 0x070A12, bg: 0x111726, surface: 0x182032, raised: 0x1F2A3E,
        field: 0x111726, codeBg: 0x0D1220,
        text: 0xE3E8F2, muted: 0x8792A8,
        accent: 0x8CA8F0, onAccent: 0x111726, accentDeep: 0xADC1F7,
        ok: 0x6FC4A8, clay: 0xE09A6B,
        invMuted: 0x5A6172
    )

    /// Ember — warm charcoal lit by amber; the night version of Slate Amber.
    static let ember = Theme.make(
        isDark: true,
        desk: 0x0C0907, bg: 0x1A1512, surface: 0x221B17, raised: 0x2B231D,
        field: 0x1A1512, codeBg: 0x140F0C,
        text: 0xEDE4DA, muted: 0x9A8B7C,
        accent: 0xE3A857, onAccent: 0x1A1512, accentDeep: 0xF0C07C,
        ok: 0x8FB98A, clay: 0xD08A64,
        invMuted: 0x6A5E53
    )

    /// Carbon — neutral graphite and ice, the highest-contrast palette here.
    static let carbon = Theme.make(
        isDark: true,
        desk: 0x000000, bg: 0x121212, surface: 0x1B1B1B, raised: 0x242424,
        field: 0x121212, codeBg: 0x0D0D0D,
        text: 0xEDEDED, muted: 0x8E8E8E,
        accent: 0x63C8D8, onAccent: 0x121212, accentDeep: 0x8CDDE9,
        ok: 0x7FC98A, clay: 0xD79A6A,
        invMuted: 0x5E5E5E
    )
}

/// The palettes a user can pick, in the order Settings lays them out.
///
/// The raw values are the on-disk preference, so `light` and `dark` keep their
/// names from when those were the only two — an existing preference still
/// resolves after the list grew.
enum ThemeMode: String, CaseIterable, Identifiable {
    case light, paper, harbor, blossom
    case dark, midnight, ember, carbon

    var id: String { rawValue }

    var theme: Theme {
        switch self {
        case .light: return .light
        case .paper: return .paper
        case .harbor: return .harbor
        case .blossom: return .blossom
        case .dark: return .dark
        case .midnight: return .midnight
        case .ember: return .ember
        case .carbon: return .carbon
        }
    }

    var label: String {
        switch self {
        case .light: return "Slate Amber"
        case .paper: return "Paper"
        case .harbor: return "Harbor"
        case .blossom: return "Blossom"
        case .dark: return "Night Moss"
        case .midnight: return "Midnight"
        case .ember: return "Ember"
        case .carbon: return "Carbon"
        }
    }

    var isDark: Bool { theme.isDark }

    static var lightModes: [ThemeMode] { allCases.filter { !$0.isDark } }
    static var darkModes: [ThemeMode] { allCases.filter(\.isDark) }
}

private struct ThemeKey: EnvironmentKey {
    // Matches `AppState.themeMode`'s default, so a view that somehow reads the
    // environment before the window injects the real palette doesn't flash the
    // wrong one.
    static let defaultValue: Theme = .dark
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    func shadow(_ spec: ShadowSpec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: 0, y: spec.y)
    }
}
