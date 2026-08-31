import SwiftUI

// Design tokens, transcribed verbatim from `Day Log.dc.html` lines 15-30.
// Light is the "Slate Amber" palette, dark is "Night Moss" — note the accent
// changes hue between them (amber -> moss), which is deliberate.

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

    static let light = Theme(
        isDark: false,
        desk: Color(hex: 0xDEE1E3),
        bg: Color(hex: 0xF1F2F3),
        surface: Color(hex: 0xFFFFFF),
        raised: Color(hex: 0xFFFFFF),
        field: Color(hex: 0xF4F5F6),
        codeBg: Color(hex: 0xF4F5F6),
        text: Color(hex: 0x1A1E22),
        muted: Color(hex: 0x7C858E),
        line: Color(hex: 0x1A1E22, alpha: 0.09),
        lineSoft: Color(hex: 0x1A1E22, alpha: 0.06),
        accent: Color(hex: 0xE09A2B),
        onAccent: Color(hex: 0x1A1E22),
        accentDeep: Color(hex: 0xB87514),
        accentSoft: Color(hex: 0xE09A2B, alpha: 0.16),
        ok: Color(hex: 0x3E7C74),
        clay: Color(hex: 0xB87514),
        invBg: Color(hex: 0x1A1E22),
        invText: Color(hex: 0xF1F2F3),
        invMuted: Color(hex: 0xF1F2F3, alpha: 0.6),
        shadowFloat: ShadowSpec(color: Color(hex: 0x1A1E22, alpha: 0.22), radius: 18, y: 14),
        shadowWin: ShadowSpec(color: Color(hex: 0x1A1E22, alpha: 0.28), radius: 35, y: 30)
    )

    static let dark = Theme(
        isDark: true,
        desk: Color(hex: 0x0A0C0D),
        bg: Color(hex: 0x14171A),
        surface: Color(hex: 0x1B1F22),
        raised: Color(hex: 0x23282B),
        field: Color(hex: 0x14171A),
        codeBg: Color(hex: 0x101314),
        text: Color(hex: 0xE8E9E6),
        muted: Color(hex: 0x8A928F),
        line: Color(hex: 0xE8E9E6, alpha: 0.10),
        lineSoft: Color(hex: 0xE8E9E6, alpha: 0.07),
        accent: Color(hex: 0x8FB98A),
        onAccent: Color(hex: 0x14171A),
        accentDeep: Color(hex: 0xA6CBA1),
        accentSoft: Color(hex: 0x8FB98A, alpha: 0.16),
        ok: Color(hex: 0x8FB98A),
        clay: Color(hex: 0xD08A64),
        invBg: Color(hex: 0xE8E9E6),
        invText: Color(hex: 0x14171A),
        invMuted: Color(hex: 0x5B615E),
        shadowFloat: ShadowSpec(color: .black.opacity(0.6), radius: 20, y: 16),
        shadowWin: ShadowSpec(color: .black.opacity(0.65), radius: 38, y: 32)
    )
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .light
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
