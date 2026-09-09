import Foundation
@testable import FoglioCore

@MainActor
func storeTests() {
    Check.suite("Note files — frontmatter") {
        var note = Note(
            title: "Operator — reconcile loop notes",
            body: "# Reconcile, don't RPC\nEvery handler is idempotent.",
            folder: .platform,
            pin: "Kubernetes, to CKA"
        )
        note.updatedAt = Date(timeIntervalSince1970: 1_756_650_000)

        let text = NoteFile.encode(note)
        let back = NoteFile.decode(text)

        Check.equal(back.title, note.title, "title survives")
        Check.equal(back.folder, note.folder, "folder survives")
        Check.equal(back.pin, note.pin, "pin survives")
        Check.equal(back.id, note.id, "id survives")
        Check.equal(back.body, note.body, "body survives")
        Check.equal(
            Int(back.updatedAt.timeIntervalSince1970),
            Int(note.updatedAt.timeIntervalSince1970),
            "timestamp survives to the second"
        )
    }

    Check.suite("Note files — awkward input") {
        // A colon in the title would break a naive `split(":")` parser.
        let note = Note(title: "Reconcile: don't RPC", body: "body", folder: .career)
        Check.equal(
            NoteFile.decode(NoteFile.encode(note)).title,
            "Reconcile: don't RPC",
            "a colon in the title round-trips"
        )

        // A hand-written file with no frontmatter is body-only, not an error.
        let bare = NoteFile.decode("# Just markdown\nno frontmatter here")
        Check.equal(bare.body, "# Just markdown\nno frontmatter here", "bare file becomes the body")
        Check.equal(bare.folder, .scratch, "bare file defaults to scratch")

        // A body containing `---` must not be mistaken for the closing fence.
        let withRule = Note(title: "T", body: "before\n---\nafter", folder: .scratch)
        Check.equal(
            NoteFile.decode(NoteFile.encode(withRule)).body,
            "before\n---\nafter",
            "a divider in the body survives"
        )
    }

    Check.suite("Note files — filenames") {
        let a = Note(title: "Operator — reconcile loop notes")
        Check.expect(
            NoteFile.filename(for: a).hasPrefix("operator-reconcile-loop-notes-"),
            "filename slugifies the title"
        )
        Check.expect(NoteFile.filename(for: a).hasSuffix(".md"), "filename ends in .md")

        // Same title, different notes — filenames must not collide.
        let b = Note(title: "Scratchpad")
        let c = Note(title: "Scratchpad")
        Check.expect(
            NoteFile.filename(for: b) != NoteFile.filename(for: c),
            "identical titles get distinct filenames"
        )

        Check.expect(
            NoteFile.filename(for: Note(title: "")).hasPrefix("untitled-"),
            "an empty title falls back to 'untitled'"
        )
    }

    Check.suite("Store — round-trips through disk") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = Store(root: root)
        store.load() // seeds on an empty directory

        Check.equal(store.notes.count, 4, "seeds four notes")
        Check.equal(store.milestones.count, 3, "seeds three milestones")
        Check.expect(store.tasks.contains { $0.done }, "seeds one completed task")

        // A second Store over the same directory must see the same data.
        let reopened = Store(root: root)
        reopened.load()
        Check.equal(reopened.notes.count, 4, "notes reload from disk")
        Check.equal(reopened.tasks.count, store.tasks.count, "tasks reload from disk")
        Check.expect(
            reopened.notes.contains { $0.title == "Operator — reconcile loop notes" },
            "a seeded note survives a reload"
        )

        // The seeded note's code block and table must survive the file round-trip
        // — this is the real end-to-end proof of the lossless markdown fix.
        let operatorNote = reopened.notes.first { $0.title == "Operator — reconcile loop notes" }
        let blocks = operatorNote?.blocks ?? []
        Check.expect(
            blocks.contains { if case .code(let lang, _) = $0 { return lang == "go" } else { return false } },
            "the Go code block survives a write/read cycle with its language"
        )
        Check.expect(
            blocks.contains { if case .table(let rows) = $0 { return rows.count == 4 } else { return false } },
            "the 4-row table survives a write/read cycle"
        )
    }

    Check.suite("Store — quick note") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = Store(root: root)
        store.load()
        let countBeforeQuickNote = store.notes.count

        let id = UUID()
        let created = store.quickNote(id: id)
        Check.equal(created.id, id, "the quick note is created with the requested id")
        Check.equal(store.notes.count, countBeforeQuickNote + 1, "creating it adds exactly one note")

        var edited = created
        edited.body = "call back re: staging access"
        store.upsert(edited)

        let fetchedAgain = store.quickNote(id: id)
        Check.equal(fetchedAgain.body, "call back re: staging access", "asking again returns the same note, not a fresh one")
        Check.equal(store.notes.count, countBeforeQuickNote + 1, "asking again doesn't create a second note")
    }

    Check.suite("Store — tasks and log") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = Store(root: root)
        store.load()

        let task = TaskItem(label: "Ship the thing", lane: .ordinary)
        store.addTask(task)
        Check.expect(store.hasTask(labelled: "Ship the thing"), "a todo reads as sent once a task exists")

        store.move(taskId: task.id, to: .delegate)
        let moved = store.tasks.first { $0.id == task.id }
        Check.equal(moved?.lane, .delegate, "task moves lane")
        Check.equal(moved?.meta, "Follow up", "moving to delegate fills in the follow-up meta")

        let logBefore = store.todaysLog.count
        store.setDone(taskId: task.id, done: true, autoLog: true)
        Check.equal(store.todaysLog.count, logBefore + 1, "completing with autoLog writes a log entry")
        Check.equal(store.todaysLog.last?.kind, .task, "the entry is a task entry")

        let logAfter = store.todaysLog.count
        let other = TaskItem(label: "Quiet one")
        store.addTask(other)
        store.setDone(taskId: other.id, done: true, autoLog: false)
        Check.equal(store.todaysLog.count, logAfter, "autoLog off writes nothing")
    }

    Check.suite("Store — pin targets") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = Store(root: root)
        store.load()

        let targets = store.pinTargets
        Check.expect(targets.contains("Kubernetes, to CKA"), "milestones are pin targets")
        Check.expect(
            targets.contains("Finish Kubernetes operator chapter"),
            "incomplete tasks are pin targets"
        )
        Check.expect(
            !targets.contains("Review platform RFC"),
            "completed tasks are not pin targets"
        )
    }
}

@MainActor
func renameTests() {
    func freshStore() -> (Store, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        let store = Store(root: root)
        store.load()
        return (store, root)
    }

    Check.suite("Renaming a note does not orphan files") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let notesDir = root.appendingPathComponent("notes")
        func fileCount() -> Int {
            ((try? FileManager.default.contentsOfDirectory(atPath: notesDir.path)) ?? [])
                .filter { $0.hasSuffix(".md") }.count
        }

        let before = fileCount()
        var note = store.newNote(in: .scratch)
        Check.equal(fileCount(), before + 1, "a new note writes one file")

        // Type a title one character at a time — the filename tracks the title,
        // so this previously left one orphaned file per keystroke.
        for title in ["T", "Te", "Tes", "Test", "Test ", "Test S", "Test Script"] {
            note.title = title
            store.upsert(note)
            note = store.note(id: note.id) ?? note
        }

        Check.equal(fileCount(), before + 1, "typing an 11-character title still leaves exactly one file")
        Check.equal(store.notes.filter { $0.id == note.id }.count, 1, "and exactly one note in memory")

        // The stale files also used to reload as duplicate notes.
        let reopened = Store(root: root)
        reopened.load()
        Check.equal(reopened.notes.count, store.notes.count, "no duplicates appear after a reload")
        Check.expect(
            reopened.notes.contains { $0.title == "Test Script" },
            "the note reloads under its final title"
        )
    }

    Check.suite("Duplicate ids left by the old bug are healed on load") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let notesDir = root.appendingPathComponent("notes")

        // Simulate the corrupted state: several files, same id, different titles.
        let id = UUID()
        for (i, title) in ["Hel", "Hell", "Hello"].enumerated() {
            var note = Note(title: title, body: "body", folder: .scratch)
            note.id = id
            note.updatedAt = Date(timeIntervalSince1970: 1_756_650_000 + Double(i))
            try? NoteFile.encode(note).write(
                to: notesDir.appendingPathComponent(NoteFile.filename(for: note)),
                atomically: true, encoding: .utf8
            )
        }
        _ = store

        let healed = Store(root: root)
        healed.load()
        Check.equal(healed.notes.filter { $0.id == id }.count, 1, "duplicates collapse to one note")
        Check.equal(
            healed.notes.first { $0.id == id }?.title,
            "Hello",
            "the most recently updated version wins"
        )

        let remaining = ((try? FileManager.default.contentsOfDirectory(atPath: notesDir.path)) ?? [])
            .filter { $0.hasPrefix("hel") }
        Check.equal(remaining.count, 1, "the stale files are deleted from disk")
    }

    Check.suite("Deleting a note") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let notesDir = root.appendingPathComponent("notes")

        func fileCount() -> Int {
            ((try? FileManager.default.contentsOfDirectory(atPath: notesDir.path)) ?? [])
                .filter { $0.hasSuffix(".md") }.count
        }

        let before = fileCount()
        var note = store.newNote(in: .scratch)
        note.title = "Throwaway"
        store.upsert(note)
        Check.equal(fileCount(), before + 1, "the note has a file to begin with")

        store.deleteNote(id: note.id)
        Check.expect(store.note(id: note.id) == nil, "the note is gone from memory")
        Check.equal(fileCount(), before, "and its file is gone from disk")

        // The bug this guards: a delete that only drops the in-memory copy
        // leaves the file behind, so the note reappears on next launch.
        let reopened = Store(root: root)
        reopened.load()
        Check.expect(
            !reopened.notes.contains { $0.id == note.id },
            "it does not come back on reload"
        )
    }

    Check.suite("Deleting a note mid-edit") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        // Typing schedules a debounced write. If the delete doesn't cancel it,
        // that write lands 400ms later and resurrects the file.
        var note = store.newNote(in: .scratch)
        note.title = "Half typed"
        store.upsert(note, debounced: true)
        store.deleteNote(id: note.id)

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let reopened = Store(root: root)
        reopened.load()
        Check.expect(
            !reopened.notes.contains { $0.id == note.id },
            "a pending save does not write the note back after it is deleted"
        )
    }
}

@MainActor
func folderTests() {
    func freshStore() -> (Store, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        let store = Store(root: root)
        store.load()
        return (store, root)
    }

    Check.suite("Folders — names, not cases") {
        // Typing the same name in two capitalisations means one folder.
        Check.equal(Folder("Reading"), Folder("reading"), "identity ignores case")
        Check.equal(Folder("Reading").label, "Reading", "the name is shown as written")

        // Files written before folders were user-made carry lowercase names.
        Check.equal(Folder("platform"), .platform, "a legacy lowercase name is the same folder")
        Check.equal(Folder("platform").label, "Platform", "and is capitalised for display")

        // Whitespace and emptiness can't produce an unreachable folder.
        Check.equal(Folder("  Ideas  ").rawValue, "Ideas", "surrounding space is trimmed")
        Check.equal(Folder(""), .scratch, "an empty name falls back to Scratch")
    }

    Check.suite("Folders — a custom name survives the file round-trip") {
        let note = Note(title: "Kettlebell log", body: "5x5", folder: Folder("Training"))
        let back = NoteFile.decode(NoteFile.encode(note))
        Check.equal(back.folder, Folder("Training"), "a folder the app didn't ship with round-trips")
        Check.equal(back.folder.rawValue, "Training", "with its capitalisation intact")

        // Frontmatter is meant to be hand-editable, so an unknown name is a
        // folder, not an error.
        let handWritten = NoteFile.decode("---\ntitle: T\nfolder: Reading list\n---\nbody")
        Check.equal(handWritten.folder, Folder("Reading list"), "a hand-typed folder is honoured")
    }

    Check.suite("Folders — creating") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        Check.equal(store.folders, Folder.starters, "a new store starts with the three seeded folders")

        let made = store.addFolder(named: "Training")
        Check.equal(made, Folder("Training"), "creating returns the new folder")
        Check.expect(store.folders.contains(Folder("Training")), "and it joins the list")

        Check.expect(store.addFolder(named: "  ") == nil, "a blank name creates nothing")
        Check.equal(store.folders.count, 4, "and doesn't grow the list")

        // Asking twice means "that folder", not a second row that looks the same.
        Check.equal(store.addFolder(named: "training"), Folder("Training"), "an existing name returns it")
        Check.equal(store.folders.count, 4, "without duplicating it")

        // An empty folder has no notes to be derived from, so it has to be
        // stored — this is the whole reason folders.json exists.
        let reopened = Store(root: root)
        reopened.load()
        Check.expect(
            reopened.folders.contains(Folder("Training")),
            "an empty folder survives a relaunch"
        )
    }

    Check.suite("Folders — moving notes") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var note = store.newNote(in: .scratch)
        note.title = "Kettlebell log"
        store.upsert(note)
        let edited = store.note(id: note.id)?.updatedAt ?? Date()

        store.move(noteIds: [note.id], to: .career)
        Check.equal(store.note(id: note.id)?.folder, .career, "the note moves")
        Check.equal(
            store.note(id: note.id)?.updatedAt,
            edited,
            "moving doesn't count as editing — the timestamp stands"
        )

        // The move has to reach disk, not just memory.
        let reopened = Store(root: root)
        reopened.load()
        Check.equal(reopened.note(id: note.id)?.folder, .career, "and it survives a reload")

        // Moving to a folder that doesn't exist yet creates it, so a note can
        // never end up somewhere the sidebar doesn't show.
        store.move(noteIds: [note.id], to: Folder("Elsewhere"))
        Check.expect(store.folders.contains(Folder("Elsewhere")), "an unknown target joins the list")
    }

    Check.suite("Folders — renaming carries the notes") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let note = store.newNote(in: .career)
        store.renameFolder(.career, to: "Job hunt")

        Check.expect(!store.folders.contains(.career), "the old name goes")
        Check.expect(store.folders.contains(Folder("Job hunt")), "the new one takes its place")
        Check.equal(
            store.note(id: note.id)?.folder,
            Folder("Job hunt"),
            "notes inside follow the rename"
        )

        let reopened = Store(root: root)
        reopened.load()
        Check.equal(reopened.note(id: note.id)?.folder, Folder("Job hunt"), "on disk too")

        // Renaming onto an existing name merges: two rows meaning one folder
        // would be indistinguishable everywhere downstream.
        store.renameFolder(Folder("Job hunt"), to: "Scratch")
        Check.equal(store.folders.filter { $0 == .scratch }.count, 1, "no duplicate row appears")
        Check.equal(store.note(id: note.id)?.folder, .scratch, "and the notes land in the survivor")
    }

    Check.suite("Folders — deleting keeps the notes") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let note = store.newNote(in: .platform)
        let countBefore = store.notes.count

        store.deleteFolder(.platform)
        Check.expect(!store.folders.contains(.platform), "the folder goes")
        Check.equal(store.notes.count, countBefore, "but none of its notes do")
        Check.equal(store.note(id: note.id)?.folder, .scratch, "they fall back to Scratch")

        // Scratch is where those notes land, so it can't be the one removed.
        store.deleteFolder(.scratch)
        Check.expect(store.folders.contains(.scratch), "Scratch stays")
    }

    Check.suite("Folders — a folder only a note knows about") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let notesDir = root.appendingPathComponent("notes")

        // What a hand-edited file, or an import, looks like: a note claiming a
        // folder the sidebar has never heard of. Without reconciliation that
        // note sits somewhere unreachable.
        let note = Note(title: "From elsewhere", body: "x", folder: Folder("Imported"))
        try? NoteFile.encode(note).write(
            to: notesDir.appendingPathComponent(NoteFile.filename(for: note)),
            atomically: true, encoding: .utf8
        )
        _ = store

        let reopened = Store(root: root)
        reopened.load()
        Check.expect(
            reopened.folders.contains(Folder("Imported")),
            "an unlisted folder is picked up from the notes on load"
        )
    }

    Check.suite("Deleting several notes at once") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let notesDir = root.appendingPathComponent("notes")

        func fileCount() -> Int {
            ((try? FileManager.default.contentsOfDirectory(atPath: notesDir.path)) ?? [])
                .filter { $0.hasSuffix(".md") }.count
        }

        let before = fileCount()
        let doomed = (0..<3).map { i -> Note in
            var note = store.newNote(in: .scratch)
            note.title = "Throwaway \(i)"
            store.upsert(note)
            return note
        }
        let keeper = store.newNote(in: .scratch)
        Check.equal(fileCount(), before + 4, "four notes, four files")

        store.deleteNotes(ids: doomed.map(\.id))
        Check.equal(fileCount(), before + 1, "only the untouched note's file is left")
        Check.expect(store.note(id: keeper.id) != nil, "and it is still there in memory")
        Check.expect(doomed.allSatisfy { store.note(id: $0.id) == nil }, "the rest are gone")
    }
}

@MainActor
func folderExportTests() {
    Check.suite("Folders — through an export and back") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = Store(root: root)
        store.load()
        store.addFolder(named: "Training")
        let filed = store.newNote(in: Folder("Reading"))

        let archive = Exporter.archive(from: store)

        let other = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: other) }
        let restored = Store(root: other)
        restored.load()
        restored.replaceAll(with: archive)

        Check.expect(
            restored.folders.contains(Folder("Training")),
            "an empty folder survives export and import"
        )
        Check.equal(
            restored.note(id: filed.id)?.folder,
            Folder("Reading"),
            "and a note keeps the folder it was filed in"
        )

        // An archive from before folders were user-made has no folder list.
        var legacy = archive
        legacy.folders = nil
        let older = Store(root: other.appendingPathComponent("older"))
        older.load()
        older.replaceAll(with: legacy)
        Check.expect(
            older.folders.contains(Folder("Reading")),
            "a folder list is rebuilt from the notes when the archive has none"
        )
    }
}
