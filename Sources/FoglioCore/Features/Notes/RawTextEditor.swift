import SwiftUI
import AppKit

/// The raw-markdown editor: one block while it's being edited (:207), or — in
/// source mode — the whole note at once.
///
/// This is an `NSTextView` rather than SwiftUI's `TextEditor` because three of
/// the design's key bindings are load-bearing and `TextEditor` won't give them
/// up: Return splits the block, Backspace in an empty block deletes it, and
/// Escape stops editing. `textView(_:doCommandBy:)` intercepts all three
/// cleanly, which `.onKeyPress` on a `TextEditor` cannot do reliably.
struct RawTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    /// Code and table blocks keep Return as a literal newline (:1106), and so
    /// does the whole-note editor.
    var allowsNewlines: Bool
    /// Extra leading between lines. The block editor takes the font's own,
    /// matching the rendered block it replaces; the source editor opens it up
    /// so a screenful of markdown isn't a wall.
    var lineSpacing: CGFloat = 0
    /// Where the caret goes when the editor appears.
    ///
    /// End-of-text is right for a block you clicked into to carry on typing.
    /// For the whole note it would scroll you to the bottom of the document
    /// the instant you switched modes, so that editor starts at the top.
    var caretAtEnd: Bool = true
    /// The shortest the editor is allowed to be.
    ///
    /// A block is as tall as its text. The whole-note editor fills the pane
    /// instead, so clicking the empty space under the last line lands in the
    /// document rather than on nothing — which is what an editor you can click
    /// anywhere in feels like.
    var minHeight: CGFloat = 20
    /// Whether Escape gives up focus as well as calling `onEscape`.
    ///
    /// The block editor has somewhere to hand focus back to — the rendered
    /// block. The source editor doesn't, and a text view that keeps first
    /// responder swallows every Escape after the first, so the window never
    /// hears the one meant for the search field.
    var escapeResignsFocus: Bool = false
    var onEnter: () -> Void
    var onBackspaceWhenEmpty: () -> Void
    var onEscape: () -> Void
    var onBlur: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SelfSizingTextView {
        let view = SelfSizingTextView()
        view.minHeight = minHeight
        view.delegate = context.coordinator
        view.isRichText = false
        view.isEditable = true
        view.drawsBackground = false
        view.allowsUndo = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.font = font
        view.textColor = textColor
        view.defaultParagraphStyle = Self.paragraphStyle(lineSpacing)
        // Set after the attributes: a plain-text view stamps whatever is
        // current onto the string it is given, so a string assigned first
        // keeps the default font and ignores the leading.
        view.typingAttributes = Self.attributes(font: font, color: textColor, lineSpacing: lineSpacing)
        view.string = text

        // Take focus as soon as the editor appears.
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            let caret = caretAtEnd ? view.string.count : 0
            view.setSelectedRange(NSRange(location: caret, length: 0))
        }
        return view
    }

    func updateNSView(_ view: SelfSizingTextView, context: Context) {
        context.coordinator.parent = self
        view.typingAttributes = Self.attributes(font: font, color: textColor, lineSpacing: lineSpacing)
        if view.string != text {
            // Reassigning the string drops the caret to the start, which is
            // only tolerable because this branch is for text that arrived from
            // somewhere other than typing — a different note, a format change.
            view.string = text
        }
        if view.font != font { view.font = font }
        view.textColor = textColor
        view.invalidateIntrinsicContentSize()
    }

    private static func paragraphStyle(_ lineSpacing: CGFloat) -> NSParagraphStyle? {
        guard lineSpacing > 0 else { return nil }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    private static func attributes(
        font: NSFont, color: NSColor, lineSpacing: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let style = paragraphStyle(lineSpacing) { attributes[.paragraphStyle] = style }
        return attributes
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RawTextEditor

        init(_ parent: RawTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? SelfSizingTextView else { return }
            parent.text = view.string
            view.invalidateIntrinsicContentSize()
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onBlur()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if parent.allowsNewlines { return false } // let it type a newline
                parent.onEnter()
                return true

            case #selector(NSResponder.deleteBackward(_:)):
                // Only intercept when the block is already empty; otherwise this
                // is an ordinary character delete.
                if textView.string.isEmpty {
                    parent.onBackspaceWhenEmpty()
                    return true
                }
                return false

            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                if parent.escapeResignsFocus { textView.window?.makeFirstResponder(nil) }
                return true

            default:
                return false
            }
        }
    }
}

/// An `NSTextView` that reports its laid-out height, so it can sit in a SwiftUI
/// stack without a scroll view and grow as you type.
final class SelfSizingTextView: NSTextView {
    var minHeight: CGFloat = 20

    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else {
            return super.intrinsicContentSize
        }
        container.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = manager.usedRect(for: container).height
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, minHeight))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }
}
