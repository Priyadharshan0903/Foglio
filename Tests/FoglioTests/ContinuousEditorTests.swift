import AppKit
@testable import FoglioCore

@MainActor
func continuousEditorTests() {
    Check.suite("Continuous notes — legacy files remain readable") {
        let bodies = [
            "", "Plain writing ✨\n\nAnother paragraph\n", "# Title\n## Heading\n### Smaller heading\nText",
            "* First\n+ Second\n- Third", "5) Fifth\n6) Sixth", "- [ ] Open\n* [X] Finished",
            "```go\n# not a heading\n- not a list\n```\nAfter", "~~~\n- [ ] code\n~~~",
            "|a|b|\n|---|---|\n|1|2|\n-----\n![diagram](image.png)\n[[Other note]]",
            "**bold** and _italic_\n[Link](https://example.com)", "# ", "## Heading\n\n### ",
        ]
        for body in bodies {
            Check.equal(NoteDocument.encode(NoteDocument.decode(body, color: .labelColor)), body,
                        "existing Markdown round-trips without rewriting")
        }
        let rich = NoteDocument.decode("# Title\n- Item\n- [x] Done", color: .labelColor)
        Check.equal(rich.string, "Title\n• Item\n☑\tDone", "headings and lists have semantic visual markers")
    }

    func editor(_ body: String) -> NoteTextView {
        let view = NoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        view.isRichText = false
        view.allowsUndo = true
        view.configureChecklists(accent: .systemOrange, ink: .black, outline: .gray)
        view.textStorage?.setAttributedString(NoteDocument.decode(body, color: .labelColor))
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        return view
    }
    func markdown(_ view: NoteTextView) -> String { NoteDocument.encode(view.textStorage!) }

    Check.suite("Continuous notes — typing lists") {
        for (body, expected) in [("- First", "- First\n- "), ("1. First", "1. First\n2. "),
                                  ("5) Fifth", "5) Fifth\n6) "), ("- [x] Done", "- [x] Done\n- [ ] ")] {
            let view = editor(body)
            view.insertNewline(nil)
            Check.equal(markdown(view), expected, "Return continues a list and resets completed checkboxes")
            view.insertNewline(nil)
            Check.equal(markdown(view), body + "\n", "Return on an empty item ends the list")
            Check.equal(view.typingAttributes[.noteStyle] as? String, NoteStyle.body.rawValue,
                        "typing after a list uses body text")
        }
        let heading = editor("# Heading")
        heading.insertNewline(nil)
        heading.insertText("Body", replacementRange: heading.selectedRange())
        Check.equal(markdown(heading), "# Heading\nBody", "Return after a heading starts regular text")

        let emoji = editor("- Plan 🧑🏽‍💻")
        emoji.insertNewline(nil)
        emoji.insertText("Ship ✨", replacementRange: emoji.selectedRange())
        Check.equal(markdown(emoji), "- Plan 🧑🏽‍💻\n- Ship ✨", "UTF-16 caret positions work with emoji")

        let middle = editor("1. First\n2. Second\n3. Third")
        middle.setSelectedRange(NSRange(location: 8, length: 0))
        middle.insertNewline(nil)
        middle.insertText("Inserted", replacementRange: middle.selectedRange())
        Check.equal(markdown(middle), "1. First\n2. Inserted\n3. Second\n4. Third", "inserting in the middle renumbers later items")

        let backspace = editor("- Existing item")
        backspace.setSelectedRange(NSRange(location: 2, length: 0))
        backspace.deleteBackward(nil)
        Check.equal(markdown(backspace), "Existing item", "Backspace at the start of an item removes the list marker")
        Check.equal(backspace.selectedRange().location, 0, "removing the marker keeps the caret at the start")

        let deletion = editor("1. First\n2. Second\n3. Third")
        deletion.setSelectedRange(NSRange(location: 9, length: 10))
        deletion.deleteBackward(nil)
        Check.equal(markdown(deletion), "1. First\n2. Third", "deleting a numbered item closes the numbering gap")

        let checklist = editor("- [ ] Remember")
        checklist.toggleChecklistAtCaret()
        Check.equal(markdown(checklist), "- [x] Remember", "checklist toggles are saved as checked Markdown")
        checklist.toggleChecklistAtCaret()
        Check.equal(markdown(checklist), "- [ ] Remember", "checked items can be reopened")
        let code = editor("```\n☐ This is code\n```")
        code.setSelectedRange(NSRange(location: 5, length: 0))
        code.toggleChecklistAtCaret()
        Check.equal(markdown(code), "```\n☐ This is code\n```", "checkbox symbols inside code are left alone")
    }

    Check.suite("Continuous notes — format selected paragraphs") {
        let view = editor("First\nSecond\nThird")
        view.setSelectedRange(NSRange(location: 0, length: 12))
        view.applyStyle(.numbered)
        Check.equal(markdown(view), "1. First\n2. Second\nThird", "a multiline selection becomes a numbered list")
        view.setSelectedRange(NSRange(location: 0, length: 18))
        view.applyStyle(.bullet)
        Check.equal(markdown(view), "- First\n- Second\nThird", "switching list styles replaces existing markers")
        view.setSelectedRange(NSRange(location: 0, length: 18))
        view.applyStyle(.body)
        Check.equal(markdown(view), "First\nSecond\nThird", "removing a list keeps all text")

        let empty = editor("")
        empty.applyStyle(.checklist)
        empty.insertText("Remember", replacementRange: empty.selectedRange())
        Check.equal(markdown(empty), "- [ ] Remember", "a checklist can start an empty note")
    }

    Check.suite("Continuous notes — checklist circles and hit targets") {
        let view = editor("- [ ] First\n- [x] Done\n- [ ] \nBody with ☐ symbol\n```\n☑ code\n```")
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        let manager = view.layoutManager as! NoteChecklistLayoutManager
        let container = view.textContainer!
        manager.ensureLayout(for: container)
        let markers = manager.markers(in: NSRange(location: 0, length: manager.numberOfGlyphs))
        Check.equal(markers.count, 3, "only checklist prefixes draw circles, including an empty item")
        Check.equal(markers.map(\.checked), [false, true, false], "circles reflect saved completion states")
        for marker in markers {
            Check.equal(manager.checklistIndex(at: NSPoint(x: marker.rect.midX, y: marker.rect.midY), in: container),
                        marker.index, "the whole circle toggles its own item")
            Check.expect(manager.checklistIndex(at: NSPoint(x: marker.rect.maxX + 10, y: marker.rect.midY), in: container) == nil,
                         "clicking text beside a circle does not complete it")
        }
        let selection = NSRange(location: view.string.utf16.count - 2, length: 1)
        view.setSelectedRange(selection)
        view.undoManager?.groupsByEvent = false
        view.undoManager?.beginUndoGrouping()
        let point = NSPoint(x: markers[0].rect.midX + view.textContainerOrigin.x,
                            y: markers[0].rect.midY + view.textContainerOrigin.y)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event)
        view.undoManager?.endUndoGrouping()
        Check.expect(markdown(view).hasPrefix("- [x] First"), "clicking a circle completes the item")
        Check.equal(view.selectedRange(), selection, "toggling keeps the existing caret and selection")
        view.undoManager?.undo()
        Check.expect(markdown(view).hasPrefix("- [ ] First"), "Undo reopens the clicked item")
        view.undoManager?.redo()
        Check.expect(markdown(view).hasPrefix("- [x] First"), "Redo completes the clicked item")

        let wrapped = editor("- [ ] " + String(repeating: "Long item ", count: 15))
        let layout = wrapped.layoutManager!
        layout.ensureLayout(for: wrapped.textContainer!)
        let firstText = layout.glyphIndexForCharacter(at: 2)
        let firstIndent = layout.lineFragmentRect(forGlyphAt: firstText, effectiveRange: nil).minX + layout.location(forGlyphAt: firstText).x
        var nextLine = NSRange()
        _ = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: &nextLine)
        let continuation = layout.lineFragmentRect(forGlyphAt: nextLine.upperBound, effectiveRange: nil).minX
            + layout.location(forGlyphAt: nextLine.upperBound).x
        Check.equal(firstIndent, continuation, "wrapped checklist text aligns below the label")
        wrapped.setSelectedRange(NSRange(location: 2, length: 0))
        wrapped.deleteBackward(nil)
        Check.expect(!markdown(wrapped).hasPrefix("- [ ]"), "Backspace at checklist text removes the circle")
    }

    Check.suite("Continuous notes — one undo history") {
        let view = editor("First\nSecond")
        view.undoManager?.groupsByEvent = false
        view.undoManager?.beginUndoGrouping()
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.applyStyle(.bullet)
        view.undoManager?.endUndoGrouping()
        Check.expect(view.undoManager?.canUndo == true, "formatting participates in Undo")
        view.undoManager?.undo()
        Check.equal(markdown(view), "First\nSecond", "Undo restores all paragraphs and their styles")
        view.undoManager?.redo()
        Check.equal(markdown(view), "- First\n- Second", "Redo restores the list")
    }
}

@MainActor
func noteTypingSaveTests() {
    Check.suite("Notes — open the requested document") {
        let state = AppState(defaults: UserDefaults(suiteName: "FoglioNavigationTest-\(UUID())")!)
        state.folderFilter = .career
        state.search = "old search"
        state.selectingNotes = true
        state.noteSelection = [UUID()]
        let meeting = Note(title: "Meeting notes", folder: .scratch)
        state.openNote(meeting, startWriting: true)
        Check.equal(state.activeNoteId, meeting.id, "an external entry point selects its note")
        Check.equal(state.folderFilter, .scratch, "the folder follows the requested note")
        Check.equal(state.search, "", "an old search cannot hide the requested note")
        Check.expect(!state.selectingNotes && state.noteSelection.isEmpty, "a previous bulk selection is cleared")
    }
    Check.suite("Continuous notes — save the latest note state") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foglio-typing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        store.load()
        var note = store.newNote(in: .scratch)
        note.title = "Latest title"
        store.upsert(note, debounced: true)
        store.move(noteIds: [note.id], to: .career)
        store.updateNoteBody(id: note.id, body: "- First\n- Second ✨")
        store.flushPendingSaves()
        let reopened = Store(root: root)
        reopened.load()
        Check.equal(reopened.note(id: note.id)?.title, "Latest title", "body typing keeps the current title")
        Check.equal(reopened.note(id: note.id)?.folder, .career, "body typing keeps the current folder")
        Check.equal(reopened.note(id: note.id)?.body, "- First\n- Second ✨", "the complete note survives a reload")
        store.trashNote(id: note.id)
        store.updateNoteBody(id: note.id, body: "late edit")
        Check.expect(store.note(id: note.id) == nil, "a late editor callback cannot resurrect a trashed note")
    }
}
