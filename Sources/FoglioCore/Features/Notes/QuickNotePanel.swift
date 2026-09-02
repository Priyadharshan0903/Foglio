import SwiftUI
import AppKit

/// Which edge of the card the pointer notch sits on — the opposite side from
/// wherever the bar ended up relative to the card (`QuickNotePanelController.position(besides:)`
/// decides which).
enum QuickNotePointerEdge {
    case top, left, right
}

/// A rounded card with a small triangular notch on one edge, like a system
/// tooltip's callout — so the card visibly points back at the bar it came from
/// rather than floating unattached next to it.
///
/// Traced as one continuous outline — corner arc, edge, corner arc, edge
/// (detouring into the notch on whichever edge has it) — rather than a
/// rounded rect and a separate triangle glued together, which left a seam
/// where a stroke traced the triangle's base as its own closed edge.
struct SpeechBubble: Shape {
    var pointerEdge: QuickNotePointerEdge
    var pointerOffset: CGFloat
    var cornerRadius: CGFloat = 12
    var notchSpan: CGFloat = 12
    var notchDepth: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var body = rect
        switch pointerEdge {
        case .top: body.origin.y += notchDepth; body.size.height -= notchDepth
        case .left: body.origin.x += notchDepth; body.size.width -= notchDepth
        case .right: body.size.width -= notchDepth
        }

        let r = min(cornerRadius, min(body.width, body.height) / 2)
        let margin = r + notchSpan / 2
        let notchX = pointerOffset.clamped(body.minX + margin, body.maxX - margin)
        let notchY = pointerOffset.clamped(body.minY + margin, body.maxY - margin)

        var path = Path()
        path.move(to: CGPoint(x: body.minX, y: body.minY + r))

        path.addArc(
            center: CGPoint(x: body.minX + r, y: body.minY + r), radius: r,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )

        if pointerEdge == .top {
            path.addLine(to: CGPoint(x: notchX - notchSpan / 2, y: body.minY))
            path.addLine(to: CGPoint(x: notchX, y: body.minY - notchDepth))
            path.addLine(to: CGPoint(x: notchX + notchSpan / 2, y: body.minY))
        }
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))

        path.addArc(
            center: CGPoint(x: body.maxX - r, y: body.minY + r), radius: r,
            startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
        )

        if pointerEdge == .right {
            path.addLine(to: CGPoint(x: body.maxX, y: notchY - notchSpan / 2))
            path.addLine(to: CGPoint(x: body.maxX + notchDepth, y: notchY))
            path.addLine(to: CGPoint(x: body.maxX, y: notchY + notchSpan / 2))
        }
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))

        path.addArc(
            center: CGPoint(x: body.maxX - r, y: body.maxY - r), radius: r,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )

        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))

        path.addArc(
            center: CGPoint(x: body.minX + r, y: body.maxY - r), radius: r,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )

        // Traversed bottom-to-top here, so the notch's near foot (larger y,
        // reached first) and far foot are the reverse of the top/right cases.
        if pointerEdge == .left {
            path.addLine(to: CGPoint(x: body.minX, y: notchY + notchSpan / 2))
            path.addLine(to: CGPoint(x: body.minX - notchDepth, y: notchY))
            path.addLine(to: CGPoint(x: body.minX, y: notchY - notchSpan / 2))
        }
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))

        path.closeSubpath()
        return path
    }
}

private extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        lower > upper ? (lower + upper) / 2 : Swift.min(Swift.max(self, lower), upper)
    }
}

/// The bar's quick-notes card — jot something without leaving whatever you're
/// in (a meeting, say) to open the full window.
///
/// Deliberately not a shrunk `NoteEditor`: this is one always-there note and a
/// plain text area, no note list, no block toolbar. The text field is a bare
/// `NSTextView` (`ZeroInsetTextView` below) rather than SwiftUI's `TextEditor`
/// — `TextEditor` carries its own built-in text-container inset that doesn't
/// line up with a plain `Text` placeholder laid over it at the same SwiftUI
/// padding, which put the caret and the "Type something…" hint at visibly
/// different starting points.
struct QuickNotePanel: View {
    @Bindable var state: AppState
    let store: Store
    let pointerEdge: QuickNotePointerEdge
    let pointerOffset: CGFloat
    var onOpenLarge: () -> Void
    var onCollapse: () -> Void

    private var theme: Theme { state.theme }

    private var note: Note { store.quickNote(id: state.quickNoteId) }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { note.body },
            set: { newValue in
                var updated = note
                updated.body = newValue
                store.upsert(updated, debounced: true)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick notes")
                    .font(Typo.sans(11, .semibold))
                    .foregroundStyle(theme.muted)
                Spacer()
                Button(action: onCollapse) {
                    Text("×")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.muted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.flat)
                .help("Collapse")
            }

            ZStack(alignment: .topLeading) {
                if note.body.isEmpty {
                    Text("Type something…")
                        .font(Typo.sans(12.5))
                        .foregroundStyle(theme.muted.opacity(0.7))
                        .allowsHitTesting(false)
                }

                ZeroInsetTextView(
                    text: bodyBinding,
                    font: Typo.sansNSFont(12.5),
                    textColor: NSColor(theme.text)
                )
            }
            .padding(6)
            .background(theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 1)
            )
            .frame(height: 160)

            Button(action: onOpenLarge) {
                Text("Open in large window")
                    .font(Typo.sans(11, .medium))
                    .foregroundStyle(theme.accentDeep)
            }
            .buttonStyle(.flat)
        }
        .padding(10)
        .padding(.top, pointerEdge == .top ? 7 : 0)
        .padding(.leading, pointerEdge == .left ? 7 : 0)
        .padding(.trailing, pointerEdge == .right ? 7 : 0)
        .frame(width: 220)
        .background(
            SpeechBubble(pointerEdge: pointerEdge, pointerOffset: pointerOffset)
                .fill(theme.raised)
        )
        .overlay(
            SpeechBubble(pointerEdge: pointerEdge, pointerOffset: pointerOffset)
                .stroke(theme.line, lineWidth: 1)
        )
    }
}

/// A scrollable `NSTextView` with its container insets zeroed out, so the
/// "Type something…" placeholder laid over it in a `ZStack` — at the same
/// SwiftUI padding — starts from exactly the same point as the real caret.
/// `TextEditor`'s own built-in inset can't be tuned to match from outside it.
private struct ZeroInsetTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.font = font
        textView.textColor = textColor

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text { textView.string = text }
        if textView.font != font { textView.font = font }
        textView.textColor = textColor
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ZeroInsetTextView
        init(_ parent: ZeroInsetTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}
