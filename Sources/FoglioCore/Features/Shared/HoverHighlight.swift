import SwiftUI

/// The `style-hover="background: var(--accent-soft)"` the design puts on rail
/// icons and toolbar buttons (Day Log.dc.html:121, :188).
///
/// Beyond matching the design, this is what tells you a target is live before
/// you commit to clicking — without it a correctly-sized hit area still feels
/// uncertain.
private struct HoverHighlight: ViewModifier {
    let theme: Theme
    var cornerRadius: CGFloat
    /// Suppressed when the element already carries a selected background.
    var active: Bool

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering && active ? theme.accentSoft : .clear)
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(_ theme: Theme, cornerRadius: CGFloat = 8, active: Bool = true) -> some View {
        modifier(HoverHighlight(theme: theme, cornerRadius: cornerRadius, active: active))
    }
}
