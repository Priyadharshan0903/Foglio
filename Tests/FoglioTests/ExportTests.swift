import Foundation
@testable import FoglioCore

@MainActor
func exportTests() {
    Check.suite("Export — bundle contents") {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-export-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = Store(root: tmp.appendingPathComponent("store"))
        store.load()

        guard let root = try? Exporter.export(Exporter.archive(from: store), to: tmp) else {
            Check.expect(false, "export threw")
            return
        }

        let fm = FileManager.default
        Check.expect(
            fm.fileExists(atPath: root.appendingPathComponent("foglio-archive.json").path),
            "writes the archive json"
        )
        Check.expect(
            fm.fileExists(atPath: root.appendingPathComponent("tasks.md").path),
            "writes tasks.md"
        )
        let noteFiles = (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("notes").path)) ?? []
        Check.equal(noteFiles.count, 4, "writes one markdown file per note")

        let logFiles = (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("log").path)) ?? []
        Check.expect(!logFiles.isEmpty, "writes a log file per day")
    }

    Check.suite("Export — round-trips losslessly") {
        // The plan's verification step: export, re-import into an empty store,
        // and the archives must match exactly.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-export-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = Store(root: tmp.appendingPathComponent("source"))
        source.load()
        source.addTask(TaskItem(label: "A task with meta", lane: .delegate, meta: "Follow up Thu"))
        source.addLog(LogEntry(text: "Something happened", kind: .manual))

        let original = Exporter.archive(from: source)
        let root = try! Exporter.export(original, to: tmp)

        let destination = Store(root: tmp.appendingPathComponent("destination"))
        destination.load()
        let imported = try! Exporter.importArchive(from: root)
        destination.replaceAll(with: imported)

        Check.equal(Exporter.archive(from: destination), original, "the whole archive survives export -> import")

        // And it must survive a full reload from disk too, not just in memory.
        let reopened = Store(root: tmp.appendingPathComponent("destination"))
        reopened.load()
        Check.equal(reopened.notes.count, original.notes.count, "notes persist after import")
        Check.equal(reopened.tasks.count, original.tasks.count, "tasks persist after import")
        Check.expect(
            reopened.tasks.contains { $0.meta == "Follow up Thu" },
            "task meta survives the whole trip"
        )
    }

    Check.suite("Export — importing replaces rather than merges") {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-export-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = Store(root: tmp.appendingPathComponent("store"))
        store.load()
        let seeded = store.notes.count

        store.replaceAll(with: Archive(notes: [Note(title: "Only me", body: "solo")]))
        Check.equal(store.notes.count, 1, "import replaces the note set")
        Check.expect(seeded > 1, "the store really did have more before")

        // Stale files must be gone from disk, not just from memory.
        let reopened = Store(root: tmp.appendingPathComponent("store"))
        reopened.load()
        Check.equal(reopened.notes.count, 1, "replaced notes are deleted from disk")
    }

    Check.suite("Export — markdown renderings") {
        let tasks = [
            TaskItem(label: "Open one", lane: .priority, meta: "Due today"),
            TaskItem(label: "Done one", lane: .ordinary, done: true, completedAt: Date()),
        ]
        let md = Exporter.tasksMarkdown(tasks)
        Check.expect(md.contains("## Priority"), "groups by lane")
        Check.expect(md.contains("- [ ] Open one — _Due today_"), "renders an open task with meta")
        Check.expect(md.contains("- [x] Done one"), "renders a completed task as checked")

        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 31; comps.hour = 9; comps.minute = 20
        let at = Calendar.current.date(from: comps)!
        let log = Exporter.logMarkdown(
            day: "2026-08-31",
            entries: [LogEntry(text: "Review platform RFC", kind: .task, at: at)]
        )
        Check.expect(log.hasPrefix("# 2026-08-31"), "log file is titled with its day")
        Check.expect(log.contains("`09:20` Review platform RFC _(task)_"), "log line carries time and kind")
    }
}
