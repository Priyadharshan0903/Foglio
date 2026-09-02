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
}
