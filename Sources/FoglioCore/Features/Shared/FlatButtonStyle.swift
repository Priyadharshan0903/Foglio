import SwiftUI

/// `.plain` but with a sane hit area and a pressed state.
///
/// SwiftUI hit-tests a button against its label's *rendered* shape, so a label
/// whose padding is transparent — or whose content is a stroked `Path`, as every
/// icon here is — is only clickable on the ink itself. That reads as broken:
/// you aim at a 34pt square and only a thin outline responds. `contentShape`
/// makes the whole frame clickable, which is what anyone expects.
///
/// The press opacity also fills a real gap. The design gives every interactive
/// element a hover and a pressed state; `.plain` gives neither.
struct FlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == FlatButtonStyle {
    /// Use instead of `.plain` for anything the user clicks.
    static var flat: FlatButtonStyle { FlatButtonStyle() }
}
