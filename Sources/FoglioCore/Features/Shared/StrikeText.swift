import SwiftUI

/// Text that wipes a strike-through across itself, left to right.
///
/// The design does this with an animated `background-size` on a gradient plus
/// `box-decoration-break: clone` (:231), which strikes every wrapped line. A
/// single overlaid `Rectangle` would only cross one line, so instead this masks
/// a struck copy of the text over an unstruck one and grows the mask — the
/// wipe reads the same and wrapping still works.
struct StrikeText: View {
    let text: String
    let struck: Bool
    var font: Font
    var color: Color
    var strikeColor: Color
    /// Animate the wipe rather than showing the settled state immediately.
    var animated: Bool = true

    @State private var progress: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .strikethrough(true, color: strikeColor)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: geo.size.width * progress)
                        }
                }
            }
            .onAppear {
                progress = struck ? 1 : 0
            }
            .onChange(of: struck) { _, nowStruck in
                guard animated else { progress = nowStruck ? 1 : 0; return }
                if nowStruck {
                    withAnimation(.easeOut(duration: 0.45)) { progress = 1 }
                } else {
                    progress = 0
                }
            }
    }
}
