import AppKit
import SwiftUI

@Observable
final class NoteEditorController {
    weak var textView: NoteTextView?
    var selectedStyle: NoteStyle = .body
    var selectedFormats: Set<InlineFormat> = []
    var hasSelection = false
    var selectionPoint = CGPoint.zero
    var selectedText = ""
    var linkRequested = false
    var errorMessage: String?
    var canUndo = false
    var canRedo = false
    var canDeleteTableRow = false
    var canDeleteTableColumn = false

    func format(_ style: NoteStyle) { textView?.applyStyle(style) }
    func toggleChecklist() { textView?.toggleChecklistAtCaret() }
    func toggle(_ format: InlineFormat) { textView?.toggleInline(format) }
    func insert(_ command: EditorCommand) { textView?.execute(command) }
    func link(label: String, url: String) { textView?.insertLink(label: label, target: url) }
    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }
}

/// One native text view provides selection across paragraphs, click-to-place,
/// standard paste, and a single undo history for the entire note.
struct ContinuousNoteEditor: NSViewRepresentable {
    let noteID: UUID
    let markdown: String
    let color: NSColor
    let checklistAccent: NSColor
    let checklistInk: NSColor
    let checklistOutline: NSColor
    let controller: NoteEditorController
    let requestFocus: Bool
    let onChange: (String) -> Void
    let onBlur: () -> Void
    var attachmentBaseURL: URL? = nil
    var accessibilityName = "Note text"
    var linkColor: NSColor? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let view = NoteTextView()
        view.delegate = context.coordinator
        view.isRichText = true
        view.isEditable = true
        view.isSelectable = true
        view.isAutomaticLinkDetectionEnabled = true
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 28, height: 20)
        view.textContainer?.lineFragmentPadding = 0
        view.setAccessibilityLabel(accessibilityName)
        view.ink = color
        view.linkTextAttributes = [.foregroundColor: linkColor ?? checklistAccent, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.selectedTextAttributes = [.backgroundColor: checklistAccent.withAlphaComponent(0.22), .foregroundColor: color]
        view.insertionPointColor = checklistAccent
        view.attachmentBaseURL = attachmentBaseURL
        view.onLinkRequest = { [weak controller] in controller?.linkRequested = true }
        view.onEditorError = { [weak controller] in controller?.errorMessage = $0 }
        view.configureChecklists(accent: checklistAccent, ink: checklistInk, outline: checklistOutline)
        view.textStorage?.setAttributedString(NoteDocument.decode(markdown, color: color, baseURL: attachmentBaseURL))
        view.typingAttributes = NoteDocument.attributes(for: .body, color: color)
        view.onDocumentChange = { [weak coordinator = context.coordinator] in coordinator?.publish() }
        controller.textView = view
        context.coordinator.noteID = noteID
        context.coordinator.lastPublished = markdown
        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        context.coordinator.observeScroll(scroll)
        if requestFocus {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NoteTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        controller.textView = view
        view.attachmentBaseURL = attachmentBaseURL
        view.linkTextAttributes = [.foregroundColor: linkColor ?? checklistAccent, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.selectedTextAttributes = [.backgroundColor: checklistAccent.withAlphaComponent(0.22), .foregroundColor: color]
        view.insertionPointColor = checklistAccent
        view.configureChecklists(accent: checklistAccent, ink: checklistInk, outline: checklistOutline)
        if coordinator.noteID != noteID || coordinator.lastPublished != markdown {
            let changedNote = coordinator.noteID != noteID
            view.textStorage?.setAttributedString(NoteDocument.decode(markdown, color: color, baseURL: attachmentBaseURL))
            view.undoManager?.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.typingAttributes = NoteDocument.attributes(for: .body, color: color)
            if changedNote { scroll.contentView.scroll(to: .zero) }
            coordinator.noteID = noteID
            coordinator.lastPublished = markdown
        }
        if view.ink != color {
            view.ink = color
            view.textStorage?.addAttribute(.foregroundColor, value: color,
                range: NSRange(location: 0, length: view.string.utf16.count))
            view.refreshInlineAppearance()
            var typing = view.typingAttributes
            typing[.foregroundColor] = color
            view.typingAttributes = InlineMarkdown.appearance(typing)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ContinuousNoteEditor
        var noteID: UUID?
        var lastPublished = ""
        private var scrollObserver: NSObjectProtocol?

        init(_ parent: ContinuousNoteEditor) { self.parent = parent }
        deinit { if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) } }

        func observeScroll(_ scroll: NSScrollView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
                self?.refreshSelection()
            }
        }

        func publish() {
            guard let view = parent.controller.textView, let storage = view.textStorage else { return }
            let value = NoteDocument.encode(storage)
            lastPublished = value
            parent.onChange(value)
            refreshSelection()
        }

        func textDidChange(_ notification: Notification) { publish() }
        func textDidEndEditing(_ notification: Notification) { parent.onBlur() }

        func textViewDidChangeSelection(_ notification: Notification) {
            refreshSelection()
        }

        private func refreshSelection() {
            guard let view = parent.controller.textView else { return }
            let style = view.currentStyle
            let selection = view.selectedRange()
            let formats = view.currentFormats
            let text = (view.string as NSString).substring(with: selection)
            var point = CGPoint.zero
            if selection.length > 0, let manager = view.layoutManager, let container = view.textContainer {
                let glyphs = manager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
                let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                point = CGPoint(x: rect.midX + view.textContainerOrigin.x - view.visibleRect.minX,
                                y: rect.minY + view.textContainerOrigin.y - view.visibleRect.minY)
            }
            // Selection notifications can arrive while SwiftUI updates AppKit.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.parent.controller.textView === view else { return }
                let controller = self.parent.controller
                controller.selectedStyle = style
                controller.selectedFormats = formats
                controller.hasSelection = selection.length > 0
                controller.selectedText = text
                controller.selectionPoint = point
                controller.canUndo = view.undoManager?.canUndo == true
                controller.canRedo = view.undoManager?.canRedo == true
                if let storage = view.textStorage, storage.length > 0 {
                    let attrs = storage.attributes(at: min(selection.location, storage.length - 1), effectiveRange: nil)
                    controller.canDeleteTableRow = (attrs[.noteTableRow] as? Int ?? 0) > 0
                    let paragraph = attrs[.paragraphStyle] as? NSParagraphStyle
                    controller.canDeleteTableColumn = ((paragraph?.textBlocks.first as? NSTextTableBlock)?.table.numberOfColumns ?? 0) > 1
                } else {
                    controller.canDeleteTableRow = false
                    controller.canDeleteTableColumn = false
                }
            }
        }
    }
}

final class NoteTextView: NSTextView {
    var ink: NSColor = .labelColor
    var onDocumentChange: (() -> Void)?
    var attachmentBaseURL: URL?
    var onLinkRequest: (() -> Void)?
    var onEditorError: ((String) -> Void)?
    var pendingSlash: NSRange?
    private let noteUndoManager = UndoManager()

    override func layout() {
        super.layout()
        guard let storage = textStorage, let container = textContainer else { return }
        let width = min(460, container.containerSize.width - container.lineFragmentPadding * 2)
        guard width > 0 else { return }
        var changed = [NSRange]()
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  storage.attribute(.noteImageMarkdown, at: range.location, effectiveRange: nil) != nil,
                  let image = attachment.image, image.size.width > 0, image.size.height > 0 else { return }
            let scale = min(1, min(width / image.size.width, 260 / image.size.height))
            let bounds = NSRect(x: 0, y: -4, width: image.size.width * scale, height: image.size.height * scale)
            if attachment.bounds != bounds { attachment.bounds = bounds; changed.append(range) }
        }
        for range in changed { layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil) }
    }

    func configureChecklists(accent: NSColor, ink: NSColor, outline: NSColor) {
        if !(layoutManager is NoteChecklistLayoutManager) {
            textContainer?.replaceLayoutManager(NoteChecklistLayoutManager())
        }
        guard let manager = layoutManager as? NoteChecklistLayoutManager else { return }
        manager.accent = accent
        manager.checkmarkInk = ink
        manager.outline = outline
        needsDisplay = true
    }

    // The window's undo manager is shared by all responders. A note needs its
    // own history so switching notes cannot undo text in a different document.
    override var undoManager: UndoManager? { noteUndoManager }

    var currentStyle: NoteStyle {
        guard let storage = textStorage, storage.length > 0 else { return .body }
        let location = min(selectedRange().location, storage.length - 1)
        return NoteStyle(rawValue: storage.attribute(.noteStyle, at: location, effectiveRange: nil) as? String ?? "") ?? .body
    }

    /// Apply to selected paragraphs using a normal text replacement so the
    /// operation participates in native undo along with typing.
    func applyStyle(_ style: NoteStyle) {
        guard currentStyle != .table else { return }
        window?.makeFirstResponder(self)
        let ns = string as NSString
        let range = ns.paragraphRange(for: selectedRange())
        let existing = attributedSubstring(forProposedRange: range, actualRange: nil)
            ?? NSAttributedString(string: "")
        let replacement = NSMutableAttributedString(string: "")
        let lines = existing.string.components(separatedBy: "\n")
        var offset = 0
        for (index, line) in lines.enumerated() {
            if index == lines.count - 1 && line.isEmpty && range.length > 0 { break }
            let content = NSMutableAttributedString(attributedString: existing.attributedSubstring(from: NSRange(location: offset, length: line.utf16.count)))
            offset += line.utf16.count + 1
            if let marker = NoteDocument.prefixMatch("^(• |[☐☑][ \\t]|[0-9]{1,9}[.)] )", in: content.string) {
                content.deleteCharacters(in: NSRange(location: 0, length: marker.utf16.count))
            }
            let attrs = NoteDocument.attributes(for: style, color: ink)
            for key in [NSAttributedString.Key.notePrefix, .noteInlineSource, .noteInlineCanonical,
                        .noteCodeID, .noteCodeFence, .noteCodeClose, .noteCodeBodyLines] {
                content.removeAttribute(key, range: NSRange(location: 0, length: content.length))
            }
            content.addAttributes(attrs, range: NSRange(location: 0, length: content.length))
            let prefix: String
            switch style {
            case .bullet: prefix = "• "
            case .numbered: prefix = "\(index + 1). "
            case .checklist: prefix = "☐\t"
            default: prefix = ""
            }
            content.insert(NSAttributedString(string: prefix, attributes: attrs), at: 0)
            if index < lines.count - 1 { content.append(NSAttributedString(string: "\n", attributes: attrs)) }
            replacement.append(content)
        }
        replace(range, with: replacement)
        refreshInlineAppearance()
        renumberLists()
        typingAttributes = NoteDocument.attributes(for: style, color: ink)
    }

    override func insertNewline(_ sender: Any?) {
        if currentStyle == .table {
            insertText("\u{2028}", replacementRange: selectedRange())
            return
        }
        let ns = string as NSString
        let range = ns.paragraphRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = ns.substring(with: range).trimmingCharacters(in: .newlines)
        let style = currentStyle
        if style == .codeBlock, line.isEmpty || line == "\u{200B}" {
            replace(range, with: NSAttributedString(string: range.upperBound < ns.length ? "\n" : "",
                                                    attributes: NoteDocument.attributes(for: .body, color: ink)))
            typingAttributes = NoteDocument.attributes(for: .body, color: ink)
            return
        }
        let marker = NoteDocument.prefixMatch("^(• |[☐☑][ \\t]|[0-9]{1,9}[.)] )", in: line)
        if let marker, line == marker {
            replace(range, with: NSAttributedString(string: range.upperBound < ns.length ? "\n" : "",
                attributes: NoteDocument.attributes(for: .body, color: ink)))
            typingAttributes = NoteDocument.attributes(for: .body, color: ink)
            return
        }
        if style == .quote && line.isEmpty {
            applyStyle(.body)
            super.insertNewline(sender)
            return
        }
        let nextStyle: NoteStyle = [.bullet, .numbered, .checklist, .quote, .codeBlock, .literal].contains(style) ? style : .body
        let prefix: String
        switch nextStyle {
        case .bullet: prefix = "• "
        case .checklist: prefix = "☐\t"
        case .numbered:
            let number = Int(line.prefix(while: { $0.isNumber })) ?? 0
            let separator = line.drop(while: { $0.isNumber }).first == ")" ? ")" : "."
            prefix = "\(number + 1)\(separator) "
        default: prefix = ""
        }
        var attrs = NoteDocument.attributes(for: nextStyle, color: ink)
        if nextStyle == .codeBlock, let storage = textStorage, range.location < storage.length {
            let previous = storage.attributes(at: range.location, effectiveRange: nil)
            for key in [NSAttributedString.Key.noteCodeID, .noteCodeFence, .noteCodeClose, .noteCodeBodyLines] { attrs[key] = previous[key] }
        }
        replace(selectedRange(), with: NSAttributedString(string: "\n" + prefix, attributes: attrs))
        renumberLists()
        typingAttributes = attrs
    }

    override func deleteBackward(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let range = ns.paragraphRange(for: NSRange(location: selection.location, length: 0))
        let line = ns.substring(with: range)
        if selection.length == 0, [.bullet, .numbered, .checklist].contains(currentStyle),
           let marker = NoteDocument.prefixMatch("^(• |[☐☑][ \\t]|[0-9]{1,9}[.)] )", in: line),
           selection.location == range.location + marker.utf16.count {
            applyStyle(.body)
            setSelectedRange(NSRange(location: range.location, length: 0))
            return
        }
        super.deleteBackward(sender)
        renumberLists()
    }

    override func deleteForward(_ sender: Any?) {
        super.deleteForward(sender)
        renumberLists()
    }

    /// Structural edits keep a numbered run in sequence, retaining the first
    /// number and each line's delimiter. Opening a note never renumbers it.
    private func renumberLists() {
        guard let storage = textStorage else { return }
        var offset = 0
        var next: Int?
        let typing = typingAttributes
        while offset < storage.length {
            let ns = storage.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: offset, length: 0))
            let line = ns.substring(with: lineRange)
            let style = storage.attribute(.noteStyle, at: offset, effectiveRange: nil) as? String
            guard style == NoteStyle.numbered.rawValue,
                  let marker = NoteDocument.prefixMatch("^[0-9]{1,9}[.)] ", in: line),
                  let number = Int(marker.prefix(while: { $0.isNumber })) else {
                next = nil
                offset = lineRange.upperBound
                continue
            }
            let expected = next ?? number
            let separator = marker.drop(while: { $0.isNumber }).first == ")" ? ")" : "."
            let updated = "\(expected)\(separator) "
            let delta = updated.utf16.count - marker.utf16.count
            if updated != marker {
                let selection = selectedRange()
                let attrs = storage.attributes(at: offset, effectiveRange: nil)
                let markerRange = NSRange(location: offset, length: marker.utf16.count)
                replace(markerRange, with: NSAttributedString(string: updated, attributes: attrs))
                let location = selection.location >= markerRange.upperBound
                    ? selection.location + delta : selection.location
                setSelectedRange(NSRange(location: max(0, min(location, storage.length)), length: 0))
            }
            next = expected + 1
            offset = lineRange.upperBound + delta
        }
        typingAttributes = typing
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let manager = layoutManager as? NoteChecklistLayoutManager, let container = textContainer {
            let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            if let index = manager.checklistIndex(at: local, in: container) {
                toggleChecklist(at: index)
                return
            }
        }
        super.mouseDown(with: event)
    }

    func toggleChecklistAtCaret() {
        toggleChecklist(at: selectedRange().location)
    }

    private func toggleChecklist(at location: Int) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let ns = string as NSString
        let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
        guard range.location < storage.length,
              storage.attribute(.noteStyle, at: range.location, effectiveRange: nil) as? String == NoteStyle.checklist.rawValue else { return }
        let char = ns.substring(with: NSRange(location: range.location, length: 1))
        guard char == "☐" || char == "☑" else { return }
        let selection = selectedRange()
        let attrs = storage.attributes(at: range.location, effectiveRange: nil)
        replace(NSRange(location: range.location, length: 1), with: NSAttributedString(
            string: char == "☐" ? "☑" : "☐", attributes: attrs))
        setSelectedRange(selection)
    }

    override func paste(_ sender: Any?) {
        if ![.codeBlock, .literal].contains(currentStyle), let text = NSPasteboard.general.string(forType: .string),
           text.range(of: #"(?m)^(#{1,6} |[-*+] |[0-9]+[.)] |> |\x60{3}|\|)|\*\*.+\*\*|\[[^\]]+\]\("#, options: .regularExpression) != nil {
            insertMarkdown(text)
        } else { pasteAsPlainText(sender) }
        renumberLists()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let value = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        if handleMarkdownPrefix(value) { return }
        super.insertText(insertString, replacementRange: replacementRange)
        didInsertEditorText(value)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleEditorKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        window?.makeFirstResponder(nil)
    }

    func replace(_ range: NSRange, with text: NSAttributedString) {
        guard shouldChangeText(in: range, replacementString: text.string) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        setSelectedRange(NSRange(location: range.location + text.length, length: 0))
        didChangeText()
    }
}
