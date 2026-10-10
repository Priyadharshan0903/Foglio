import AppKit
@testable import FoglioCore

@MainActor
func richEditorTests() {
    func editor(_ body: String) -> NoteTextView {
        let view = NoteTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))
        view.isRichText = true
        view.allowsUndo = true
        view.textStorage?.setAttributedString(NoteDocument.decode(body, color: .labelColor))
        view.typingAttributes = NoteDocument.attributes(for: .body, color: .labelColor)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        return view
    }
    func markdown(_ view: NoteTextView) -> String { NoteDocument.encode(view.textStorage!) }
    Check.suite("Rich editor — Markdown fidelity") {
        let samples = [
            "**Bold** and _italic_ with ~~removed~~ and <u>underlined</u>",
            "__bold__ and *italic*", "**Bold _nested italic_ text**",
            "\u{0060}a_*literal*\u{0060}", "[**Bold link**](https://example.com/page)",
            "Escaped \\*literal\\* and \\[text\\]", "Plain [brackets] and file_name.txt",
            "### Heading three\n#### Heading four\n> **A quote**\n---",
            "\u{0060}\u{0060}\u{0060}swift\nlet value = 1\nprint(value)\n\u{0060}\u{0060}\u{0060}\nAfter",
            "\u{0060}\u{0060}\u{0060}\n\u{0060}\u{0060}\u{0060}", "\u{0060}\u{0060}\u{0060}\n\n\u{0060}\u{0060}\u{0060}",
            "\u{0060}\u{0060}\u{0060}", "\u{0060}\u{0060}\u{0060}\nUnclosed block",
            "| Name | Price |\n| :--- | ---: |\n| **Storage** | ₹75 |\nAfter",
            "|a|b|\n|---|---|\n|1|2|", "| A | B |\n| --- | --- |\n| | |",
            "Plan 🧑🏽‍💻 **Ship ✨**\n- [x] **Done**\n- [ ] _Next_",
            "| A | B |\n| --- | --- |\n| One | Two | Three |",
        ]
        for source in samples {
            Check.equal(NoteDocument.encode(NoteDocument.decode(source, color: .labelColor)), source,
                        "formatted documents retain their original Markdown")
        }
        let rich = NoteDocument.decode("**Bold** _Italic_ ~~Old~~ <u>Underlined</u> \u{0060}code\u{0060}", color: .labelColor)
        Check.equal(rich.string, "Bold Italic Old Underlined code", "inline markup becomes editable styled text")
        Check.expect(rich.attribute(InlineFormat.bold.key, at: 0, effectiveRange: nil) != nil, "bold text carries a semantic mark")
        let unsafe = NoteDocument.decode("[Unsafe](javascript:alert)", color: .labelColor)
        Check.expect(unsafe.attribute(.link, at: 0, effectiveRange: nil) == nil, "unsupported URL schemes do not become clickable")
        Check.equal(NoteDocument.decode(#"C:\Users\notes"#, color: .labelColor).string,
                    #"C:\Users\notes"#, "ordinary backslashes are preserved in editable prose")
    }
    Check.suite("Rich editor — selections, typing and undo") {
        let view = editor("Ship the update")
        view.undoManager?.groupsByEvent = false
        view.undoManager?.beginUndoGrouping()
        view.setSelectedRange(NSRange(location: 0, length: 4))
        view.toggleInline(.bold)
        view.undoManager?.endUndoGrouping()
        Check.equal(markdown(view), "**Ship** the update", "bold applies to the selected text")
        Check.equal(view.selectedRange(), NSRange(location: 0, length: 4), "formatting keeps the selection")
        view.undoManager?.undo()
        Check.equal(markdown(view), "Ship the update", "Undo removes selected formatting")
        view.undoManager?.redo()
        Check.equal(markdown(view), "**Ship** the update", "Redo restores selected formatting")
        view.setSelectedRange(NSRange(location: 0, length: 4))
        view.undoManager?.beginUndoGrouping()
        view.applyStyle(.heading)
        view.undoManager?.endUndoGrouping()
        Check.equal(markdown(view), "## **Ship** the update", "block formatting retains inline styling")

        let overlap = editor("abcdef")
        overlap.setSelectedRange(NSRange(location: 0, length: 4)); overlap.toggleInline(.bold)
        overlap.setSelectedRange(NSRange(location: 2, length: 4)); overlap.toggleInline(.italic)
        let saved = markdown(overlap)
        let reopened = NoteDocument.decode(saved, color: .labelColor)
        Check.equal(reopened.string, "abcdef", "overlapping formatting reopens without visible markers")
        Check.expect(reopened.attribute(InlineFormat.bold.key, at: 2, effectiveRange: nil) != nil
                     && reopened.attribute(InlineFormat.italic.key, at: 2, effectiveRange: nil) != nil,
                     "overlapping ranges retain both styles")

        let typing = editor("")
        typing.toggleInline(.bold)
        typing.insertText("Hello", replacementRange: typing.selectedRange())
        typing.toggleInline(.bold)
        typing.insertText(" world", replacementRange: typing.selectedRange())
        Check.equal(markdown(typing), "**Hello** world", "format toggles also apply to future typing")
        let automatic = editor("")
        for character in "**Hello**" { automatic.insertText(String(character), replacementRange: automatic.selectedRange()) }
        Check.equal(automatic.string, "Hello", "typed Markdown converts when its closing delimiter arrives")
        Check.equal(markdown(automatic), "**Hello**", "automatic conversion saves the same formatting")
        let heading = editor("##")
        heading.insertText(" ", replacementRange: heading.selectedRange())
        heading.insertText("Heading", replacementRange: heading.selectedRange())
        Check.equal(markdown(heading), "## Heading", "a typed heading shortcut produces a semantic heading")

        let link = editor("Read this")
        link.setSelectedRange(NSRange(location: 0, length: 4))
        link.insertLink(label: "Docs", target: "https://example.com")
        Check.equal(markdown(link), "[Docs](https://example.com) this", "a link replaces only the selected text")
        Check.expect(link.textStorage?.attribute(.link, at: 0, effectiveRange: nil) != nil, "inserted links are clickable")
        link.setSelectedRange(NSRange(location: 0, length: 4))
        link.removeLink()
        Check.equal(markdown(link), "Docs this", "removing a link keeps its label")
        let pasted = editor("")
        pasted.insertMarkdown("## Project\n- [ ] **Review**\n> Context")
        Check.equal(markdown(pasted), "## Project\n- [ ] **Review**\n> Context", "pasted Markdown retains block and inline formatting")
    }
    Check.suite("Rich editor — code and editable tables") {
        let code = editor("\u{0060}\u{0060}\u{0060}swift\nlet a = 1\n\u{0060}\u{0060}\u{0060}")
        Check.equal(code.string, "let a = 1", "code fence syntax is hidden in the editor")
        code.insertNewline(nil)
        code.insertText("let b = 2", replacementRange: code.selectedRange())
        Check.equal(markdown(code), "\u{0060}\u{0060}\u{0060}swift\nlet a = 1\nlet b = 2\n\u{0060}\u{0060}\u{0060}", "new code lines remain inside the same fence")
        code.insertNewline(nil); code.insertNewline(nil)
        code.insertText("After", replacementRange: code.selectedRange())
        Check.expect(markdown(code).hasSuffix("\u{0060}\u{0060}\u{0060}\nAfter"), "a second Return exits an empty code line")
        let table = editor("| Name | Price |\n| --- | --- |\n| Storage | ₹75 |")
        Check.expect((table.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.first is NSTextTableBlock,
                     "tables render as native editable cells")
        let layout = table.layoutManager!
        layout.ensureLayout(for: table.textContainer!)
        let rightCell = table.textStorage!.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as! NSParagraphStyle
        let rightBlock = rightCell.textBlocks.first!
        let rightBounds = layout.boundsRect(for: rightBlock, at: layout.glyphIndexForCharacter(at: 5), effectiveRange: nil)
        Check.expect(rightBounds.maxX <= table.textContainer!.containerSize.width,
                     "table borders fit inside the editor (\(rightBounds.maxX) ≤ \(table.textContainer!.containerSize.width))")
        let target = (table.string as NSString).range(of: "Storage")
        table.setSelectedRange(target)
        table.insertText("Cloud", replacementRange: target)
        Check.expect(markdown(table).contains("| Cloud | ₹75 |"), "editing a cell updates the Markdown table")
        let position = (table.string as NSString).range(of: "Cloud").upperBound
        table.setSelectedRange(NSRange(location: position, length: 0)); table.insertNewline(nil)
        table.insertText("backup", replacementRange: table.selectedRange())
        Check.expect(markdown(table).contains("Cloud<br>backup"), "Return inside a cell preserves the table structure")
        table.editTable(.addRow)
        Check.expect(markdown(table).hasSuffix("|  |  |"), "a table can grow another editable row")
        table.editTable(.addColumn)
        Check.expect(markdown(table).contains("Column 3"), "a table can grow another editable column")
        table.setSelectedRange((table.string as NSString).range(of: "Column 3"))
        table.editTable(.deleteColumn)
        Check.expect(!markdown(table).contains("Column 3"), "deleting a column preserves the remaining cells")
        table.editTable(.remove)
        Check.expect(!markdown(table).contains("| ---"), "converting a table to text retains its contents")
    }
}

@MainActor
func taskWorkflowTests() {
    Check.suite("Task board — old files and durable status transitions") {
        for done in [false, true] {
            let old = TaskItem(label: "Legacy", done: done)
            let data = try! JSONEncoder().encode(old)
            let decoded = try! JSONDecoder().decode(TaskItem.self, from: data)
            Check.equal(decoded.workflowStatus, done ? .done : .todo, "legacy tasks derive a safe workflow")
        }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foglio-workflow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root); store.load()
        let task = TaskItem(label: "Build the board", lane: store.defaultLane, meta: "**Keep** the details")
        store.addTask(task)
        for status in [TaskWorkflow.backlog, .inProgress, .done] {
            store.setWorkflow(taskId: task.id, status: status, autoLog: true)
            Check.equal(store.tasks.first?.workflowStatus, status, "moving a card updates its workflow")
        }
        let completion = store.tasks.first?.completedAt
        let logs = store.log.count
        store.setWorkflow(taskId: task.id, status: .done, autoLog: true)
        Check.equal(store.log.count, logs, "dropping into Done again does not duplicate the activity log")
        Check.equal(store.tasks.first?.completedAt, completion, "a repeated Done action keeps its completion date")
        store.setWorkflow(taskId: task.id, status: .inProgress, autoLog: false)
        Check.expect(store.tasks.first?.done == false && store.tasks.first?.completedAt == nil, "reopening clears the completed state")
        let reopened = Store(root: root); reopened.load()
        Check.equal(reopened.tasks.first?.workflowStatus, .inProgress, "workflow survives a relaunch")
        Check.equal(reopened.tasks.first?.lane, task.lane, "moving status preserves the existing list")
        Check.equal(reopened.tasks.first?.meta, task.meta, "moving status preserves rich descriptions")
        let defaults = UserDefaults(suiteName: "FoglioBoardTest-\(UUID())")!
        let state = AppState(defaults: defaults)
        Check.equal(state.taskLayout, .board, "new users start in board view")
        state.taskLayout = .list
        Check.equal(AppState(defaults: defaults).taskLayout, .list, "the layout preference survives relaunch")
    }
}

@MainActor
func attachmentTests() {
    Check.suite("Rich editor — portable file attachments") {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foglio-attachments-\(UUID())")
        try! FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let source = temp.appendingPathComponent("reference.txt")
        try! Data("Keep this reference".utf8).write(to: source)
        let store = Store(root: temp.appendingPathComponent("library")); store.load()
        let path = try! LibraryAttachments.copy(source, into: store.root)
        let body = "[Reference](\(path))"
        let note = Note(title: "References", body: body); store.upsert(note)
        let rich = NoteDocument.decode(body, color: .labelColor, baseURL: store.root)
        Check.equal(NoteDocument.encode(rich), body, "attachment links retain their relative path")
        Check.equal(rich.attribute(.link, at: 0, effectiveRange: nil) as? URL, store.root.appendingPathComponent(path), "files open from the library copy")
        let image = NSImage(size: NSSize(width: 40, height: 20))
        image.lockFocus()
        NSColor.gray.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 20).fill()
        image.unlockFocus()
        let imageFile = temp.appendingPathComponent("sample.tiff")
        try! image.tiffRepresentation!.write(to: imageFile)
        let imagePath = try! LibraryAttachments.copy(imageFile, into: store.root)
        let imageBody = "![Preview](\(imagePath))"
        let imageRich = NoteDocument.decode(imageBody, color: .labelColor, baseURL: store.root)
        Check.expect(imageRich.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment, "local images render as image attachments")
        Check.equal(NoteDocument.encode(imageRich), imageBody, "image previews save back to portable Markdown")
        let archive = Exporter.archive(from: store)
        Check.equal(archive.attachments?.count, 2, "export carries attached files and images")
        let folder = try! Exporter.export(archive, to: temp)
        Check.expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path), "readable exports contain the attachment")
        let target = Store(root: temp.appendingPathComponent("target")); target.load()
        target.replaceAll(with: try! Exporter.importArchive(from: folder))
        Check.equal(try! Data(contentsOf: target.root.appendingPathComponent(path)), Data("Keep this reference".utf8), "import restores attachment data")
        Check.expect(InlineMarkdown.attachmentURL("attachments/../../secret", baseURL: store.root) == nil, "relative attachment links stay inside their directory")
        try! LibraryAttachments.restore(["../outside.txt": Data()], at: target.root)
        Check.expect(!FileManager.default.fileExists(atPath: target.root.appendingPathComponent("outside.txt").path), "archive filenames cannot escape the attachment directory")
    }
}
