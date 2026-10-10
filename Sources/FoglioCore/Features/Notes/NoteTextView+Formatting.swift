import AppKit

enum EditorCommand: String, CaseIterable {
    case body, heading1, heading2, heading3, heading4, bullet, numbered, checklist, quote
    case codeBlock, divider, table, link, date, attachment, emoji, copyMarkdown
    var label: String {
        switch self {
        case .body: "Body text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .heading4: "Heading 4"
        case .bullet: "Bulleted list"
        case .numbered: "Numbered list"
        case .checklist: "Checklist"
        case .quote: "Quote"
        case .codeBlock: "Code block"
        case .divider: "Divider"
        case .table: "Table"
        case .link: "Link"
        case .date: "Date"
        case .attachment: "File or image"
        case .emoji: "Emoji"
        case .copyMarkdown: "Copy as Markdown"
        }
    }
}

extension NoteTextView {
    var currentFormats: Set<InlineFormat> {
        let attrs: [NSAttributedString.Key: Any]
        if selectedRange().length > 0, let storage = textStorage {
            attrs = storage.attributes(at: selectedRange().location, effectiveRange: nil)
        } else { attrs = typingAttributes }
        return Set(InlineFormat.allCases.filter { attrs[$0.key] != nil })
    }

    func toggleInline(_ format: InlineFormat) {
        guard ![.codeBlock, .literal].contains(currentStyle) else { return }
        window?.makeFirstResponder(self)
        let selection = selectedRange()
        let remove = currentFormats.contains(format)
        let delimiter: String
        switch format {
        case .bold: delimiter = "**"
        case .italic: delimiter = "_"
        case .underline: delimiter = "<u>"
        case .strike: delimiter = "~~"
        case .code: delimiter = "\u{0060}"
        }
        if selection.length == 0 {
            var attrs = typingAttributes
            if remove { attrs.removeValue(forKey: format.key) } else { attrs[format.key] = delimiter }
            typingAttributes = InlineMarkdown.appearance(attrs)
            return
        }
        guard let storage = textStorage else { return }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: selection))
        if remove { replacement.removeAttribute(format.key, range: NSRange(location: 0, length: replacement.length)) }
        else { replacement.addAttribute(format.key, value: delimiter, range: NSRange(location: 0, length: replacement.length)) }
        var codeRanges = [NSRange]()
        replacement.enumerateAttribute(.noteStyle, in: NSRange(location: 0, length: replacement.length)) { value, range, _ in
            if value as? String == NoteStyle.codeBlock.rawValue || value as? String == NoteStyle.literal.rawValue { codeRanges.append(range) }
        }
        for range in codeRanges { replacement.removeAttribute(format.key, range: range) }
        restyle(replacement)
        replace(selection, with: replacement)
        setSelectedRange(selection)
    }

    func refreshInlineAppearance() {
        guard let storage = textStorage else { return }
        restyle(storage)
    }

    private func restyle(_ text: NSMutableAttributedString) {
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            runs.append((range, InlineMarkdown.appearance(attrs)))
        }
        for (range, attrs) in runs { text.setAttributes(attrs, range: range) }
    }

    func insertLink(label: String, target: String) {
        guard InlineMarkdown.safeURL(target) != nil || InlineMarkdown.attachmentURL(target, baseURL: attachmentBaseURL) != nil else { return }
        let selection = selectedRange()
        var attrs = NoteDocument.attributes(for: currentStyle, color: ink)
        attrs[.noteLink] = target
        attrs[.link] = InlineMarkdown.safeURL(target) ?? InlineMarkdown.attachmentURL(target, baseURL: attachmentBaseURL)
        let text = label.isEmpty ? target : label
        replace(selection, with: NSAttributedString(string: text, attributes: InlineMarkdown.appearance(attrs)))
        typingAttributes = NoteDocument.attributes(for: currentStyle, color: ink)
        window?.makeFirstResponder(self)
    }

    func removeLink() {
        guard let storage = textStorage, selectedRange().length > 0 else { return }
        let selection = selectedRange()
        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: selection))
        for key in [NSAttributedString.Key.noteLink, .link] { copy.removeAttribute(key, range: NSRange(location: 0, length: copy.length)) }
        restyle(copy)
        replace(selection, with: copy)
        setSelectedRange(selection)
    }

    func execute(_ command: EditorCommand) {
        window?.makeFirstResponder(self)
        switch command {
        case .body: applyStyle(.body)
        case .heading1: applyStyle(.title)
        case .heading2: applyStyle(.heading)
        case .heading3: applyStyle(.heading3)
        case .heading4: applyStyle(.heading4)
        case .bullet: applyStyle(.bullet)
        case .numbered: applyStyle(.numbered)
        case .checklist: applyStyle(.checklist)
        case .quote: applyStyle(.quote)
        case .codeBlock: insertBlock("\u{0060}\u{0060}\u{0060}\nCode\n\u{0060}\u{0060}\u{0060}")
        case .divider: insertBlock("---")
        case .table: insertBlock("| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |")
        case .link: onLinkRequest?()
        case .date:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            insertText(formatter.string(from: Date()), replacementRange: selectedRange())
        case .emoji: NSApp.orderFrontCharacterPalette(nil)
        case .attachment: chooseAttachments()
        case .copyMarkdown:
            guard let storage = textStorage else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(NoteDocument.encode(storage), forType: .string)
        }
    }

    func insertMarkdown(_ markdown: String) {
        replace(selectedRange(), with: NoteDocument.decode(markdown, color: ink, baseURL: attachmentBaseURL))
        typingAttributes = NoteDocument.attributes(for: currentStyle, color: ink)
    }

    private func insertBlock(_ markdown: String) {
        let ns = string as NSString
        let selection = selectedRange()
        let paragraph = ns.paragraphRange(for: selection)
        let before = ns.substring(with: NSRange(location: paragraph.location, length: selection.location - paragraph.location))
        let prefix = before.isEmpty || before.hasSuffix("\n") ? "" : "\n"
        insertMarkdown(prefix + markdown + "\n")
        typingAttributes = NoteDocument.attributes(for: .body, color: ink)
    }

    private func chooseAttachments() {
        guard let root = attachmentBaseURL else {
            onEditorError?("Open a saved document before attaching a file.")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Add files or images to this document."
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self else { return }
            do {
                let markdown = try panel.urls.map { source -> String in
                    let path = try LibraryAttachments.copy(source, into: root)
                    let label = source.lastPathComponent.replacingOccurrences(of: "]", with: "").replacingOccurrences(of: "[", with: "")
                    let image = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp"].contains(source.pathExtension.lowercased())
                    return (image ? "!" : "") + "[\(label)](\(path))"
                }.joined(separator: "\n")
                self.insertBlock(markdown)
            } catch { self.onEditorError?(error.localizedDescription) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    func handleEditorKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.contains(.shift) {
            switch key {
            case "s": toggleInline(.strike)
            case "7", "&": applyStyle(.checklist)
            case "8", "*": applyStyle(.bullet)
            case "9", "(": applyStyle(.numbered)
            case "\\", "|": execute(.codeBlock)
            case "u": execute(.attachment)
            default: return false
            }
        } else {
            switch key {
            case "b": toggleInline(.bold)
            case "i": toggleInline(.italic)
            case "u": toggleInline(.underline)
            case "e": toggleInline(.code)
            case "k": if ![.codeBlock, .literal].contains(currentStyle) { onLinkRequest?() }
            case "\r": guard currentStyle == .checklist else { return false }; toggleChecklistAtCaret()
            default: return false
            }
        }
        return true
    }

    /// Markdown shortcuts apply only to a complete prefix at the caret.
    func handleMarkdownPrefix(_ text: String) -> Bool {
        guard text == " ", selectedRange().length == 0, ![.codeBlock, .literal].contains(currentStyle) else { return false }
        let ns = string as NSString
        let selection = selectedRange()
        let range = ns.paragraphRange(for: NSRange(location: selection.location, length: 0))
        let prefix = ns.substring(with: NSRange(location: range.location, length: selection.location - range.location))
        let style: NoteStyle
        switch prefix {
        case "#": style = .title
        case "##": style = .heading
        case "###": style = .heading3
        case "####": style = .heading4
        case "-", "*", "+": style = .bullet
        case "1.", "1)": style = .numbered
        case "[]", "[ ]", "- [ ]", "• []", "• [ ]": style = .checklist
        case ">": style = .quote
        case "---", "___":
            replace(NSRange(location: range.location, length: prefix.utf16.count), with: NSAttributedString(string: "", attributes: NoteDocument.attributes(for: .body, color: ink)))
            execute(.divider)
            return true
        case "\u{0060}\u{0060}\u{0060}":
            replace(NSRange(location: range.location, length: prefix.utf16.count), with: NSAttributedString(string: "", attributes: NoteDocument.attributes(for: .body, color: ink)))
            execute(.codeBlock)
            return true
        default: return false
        }
        replace(NSRange(location: range.location, length: prefix.utf16.count), with: NSAttributedString(string: "", attributes: NoteDocument.attributes(for: .body, color: ink)))
        applyStyle(style)
        return true
    }

    func didInsertEditorText(_ text: String) {
        let selection = selectedRange()
        let ns = string as NSString
        let range = ns.paragraphRange(for: NSRange(location: selection.location, length: 0))
        if text == "/", selection.location == range.location + 1, ![.literal, .codeBlock, .table].contains(currentStyle) {
            pendingSlash = NSRange(location: range.location, length: 1)
            DispatchQueue.main.async { [weak self] in self?.showSlashMenu() }
        }
        guard ["*", "_", "~", "\u{0060}", ")", ">"].contains(text), ![.literal, .codeBlock].contains(currentStyle),
              selection.location == range.upperBound || (selection.location == range.upperBound - 1 && ns.substring(with: NSRange(location: range.upperBound - 1, length: 1)) == "\n"),
              let storage = textStorage else { return }
        let length = ns.substring(with: range).trimmingCharacters(in: .newlines).utf16.count
        let lineRange = NSRange(location: range.location, length: length)
        let existing = storage.attributedSubstring(from: lineRange)
        var source = ""
        existing.enumerateAttributes(in: NSRange(location: 0, length: existing.length)) { attrs, run, _ in
            let rich = existing.attributedSubstring(from: run)
            if InlineFormat.allCases.contains(where: { attrs[$0.key] != nil }) || attrs[.noteLink] != nil {
                source += InlineMarkdown.encode(rich)
            } else { source += rich.string }
        }
        let replacement = InlineMarkdown.decode(source, attributes: NoteDocument.attributes(for: currentStyle, color: ink), baseURL: attachmentBaseURL)
        if replacement.string != existing.string {
            replace(lineRange, with: replacement)
            setSelectedRange(NSRange(location: range.location + replacement.length, length: 0))
            typingAttributes = NoteDocument.attributes(for: currentStyle, color: ink)
        }
    }

    private func showSlashMenu() {
        guard let pendingSlash, (string as NSString).length > pendingSlash.location,
              (string as NSString).substring(with: pendingSlash) == "/" else { return }
        let menu = NSMenu()
        for command in EditorCommand.allCases {
            let item = NSMenuItem(title: command.label, action: #selector(chooseSlashCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command.rawValue
            menu.addItem(item)
        }
        let rect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        if let window {
            let point = convert(window.convertPoint(fromScreen: NSPoint(x: rect.minX, y: rect.minY)), from: nil)
            menu.popUp(positioning: nil, at: point, in: self)
        }
        self.pendingSlash = nil
    }

    @objc private func chooseSlashCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = EditorCommand(rawValue: raw) else { return }
        if let pendingSlash, pendingSlash.upperBound <= string.utf16.count {
            replace(pendingSlash, with: NSAttributedString(string: "", attributes: NoteDocument.attributes(for: .body, color: ink)))
        }
        execute(command)
    }
}
