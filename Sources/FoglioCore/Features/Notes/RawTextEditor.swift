import SwiftUI
import AppKit

/// The raw-markdown editor shown when a block is being edited (:207).
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
    /// Code and table blocks keep Return as a literal newline (:1106).
    var allowsNewlines: Bool
    var onEnter: () -> Void
    var onBackspaceWhenEmpty: () -> Void
    var onEscape: () -> Void
    var onBlur: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SelfSizingTextView {
        let view = SelfSizingTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.isEditable = true
        view.drawsBackground = false
        view.allowsUndo = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.string = text
        view.font = font
        view.textColor = textColor

        // Take focus as soon as the block enters edit mode.
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: view.string.count, length: 0))
        }
        return view
    }

    func updateNSView(_ view: SelfSizingTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text { view.string = text }
        if view.font != font { view.font = font }
        view.textColor = textColor
        view.invalidateIntrinsicContentSize()
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
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else {
            return super.intrinsicContentSize
        }
        container.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = manager.usedRect(for: container).height
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, 20))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }
}
