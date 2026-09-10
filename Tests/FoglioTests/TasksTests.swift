import Foundation
@testable import FoglioCore

@MainActor
func tasksTests() {
    func freshStore() -> (Store, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        let store = Store(root: root)
        store.load()
        return (store, root)
    }

    Check.suite("Clock") {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 31
        comps.hour = 9; comps.minute = 5
        let date = Calendar.current.date(from: comps)!
        Check.equal(Clock.hhmm(date), "09:05", "single-digit hours and minutes are zero-padded")
    }

    Check.suite("Completing a task") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let task = TaskItem(label: "Ship it", lane: .priority)
        store.addTask(task)

        store.setDone(taskId: task.id, done: true, autoLog: true)
        let completed = store.tasks.first { $0.id == task.id }
        Check.expect(completed?.done == true, "task is marked done")
        Check.expect(completed?.completedAt != nil, "completedAt is stamped")
        Check.equal(store.log.last?.text, "Ship it", "the log entry carries the task's label")

        store.setDone(taskId: task.id, done: false, autoLog: false)
        let reopened = store.tasks.first { $0.id == task.id }
        Check.expect(reopened?.done == false, "task can be un-completed")
        Check.expect(
            reopened?.completedAt == nil,
            "un-completing clears completedAt, so it leaves 'Completed today'"
        )
    }

    Check.suite("Lanes") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let task = TaskItem(label: "Move me", lane: .priority)
        store.addTask(task)

        store.move(taskId: task.id, to: .ordinary)
        Check.equal(store.tasks.first { $0.id == task.id }?.lane, .ordinary, "moves to ordinary")
        Check.equal(
            store.tasks.first { $0.id == task.id }?.meta,
            "",
            "moving to a non-delegate lane adds no meta"
        )

        store.move(taskId: task.id, to: .delegate)
        Check.equal(
            store.tasks.first { $0.id == task.id }?.meta,
            "Follow up",
            "moving to delegate fills in follow-up meta"
        )

        // An existing meta must not be overwritten by the delegate default.
        let withMeta = TaskItem(label: "Has meta", lane: .priority, meta: "Due today")
        store.addTask(withMeta)
        store.move(taskId: withMeta.id, to: .delegate)
        Check.equal(
            store.tasks.first { $0.id == withMeta.id }?.meta,
            "Due today",
            "an existing meta survives a move to delegate"
        )
    }

    Check.suite("Today's log") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let todayCount = store.todaysLog.count
        store.addLog(LogEntry(text: "Pairing with Arun", kind: .manual))
        Check.equal(store.todaysLog.count, todayCount + 1, "a new entry lands in today")

        // An entry from last week must not show up under Today.
        let old = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
        store.addLog(LogEntry(text: "Ancient history", kind: .manual, at: old))
        Check.equal(store.todaysLog.count, todayCount + 1, "older entries are excluded from today")
        Check.expect(
            store.log.contains { $0.text == "Ancient history" },
            "but they are still kept in the full log"
        )
    }
}

@MainActor
func laneTests() {
    func freshStore() -> (Store, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        let store = Store(root: root)
        store.load()
        return (store, root)
    }

    Check.suite("Lanes — names, not cases") {
        // Typing the same name in two capitalisations means one column.
        Check.equal(Lane("Blocked"), Lane("blocked"), "identity ignores case")
        Check.equal(Lane("Blocked").label, "Blocked", "the name is shown as written")

        // tasks.json written by the enum version stored lowercase raw values.
        Check.equal(Lane("priority"), .priority, "a legacy lowercase lane is the same lane")
        Check.equal(Lane("priority").label, "Priority", "and is capitalised for display")

        // Whitespace and emptiness can't produce an unreachable column.
        Check.equal(Lane("  This week  ").rawValue, "This week", "surrounding space is trimmed")
        Check.equal(Lane(""), .priority, "an empty name falls back to the first shipped lane")

        Check.equal(Lane("Blocked").emptyText, "Nothing here.", "a user-made lane gets neutral empty copy")
        Check.equal(Lane("delegate").emptyText, "No follow ups.", "a shipped lane keeps its own")
    }

    Check.suite("Lanes — creating") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        Check.equal(store.lanes, Lane.starters, "a new store starts with the three seeded lanes")

        let made = store.addLane(named: "Blocked")
        Check.equal(made, Lane("Blocked"), "creating returns the new lane")
        Check.equal(store.lanes.last, Lane("Blocked"), "and it joins the end of the board")

        Check.expect(store.addLane(named: "   ") == nil, "a blank name creates nothing")
        Check.equal(store.lanes.count, 4, "and doesn't grow the board")

        Check.equal(store.addLane(named: "blocked"), Lane("Blocked"), "an existing name returns it")
        Check.equal(store.lanes.count, 4, "without duplicating the column")

        // An empty lane has no tasks to be derived from — this is why
        // lanes.json exists at all.
        let reopened = Store(root: root)
        reopened.load()
        Check.expect(reopened.lanes.contains(Lane("Blocked")), "an empty lane survives a relaunch")
    }

    Check.suite("Lanes — reordering") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        store.moveLane(.delegate, to: 0)
        Check.equal(
            store.lanes.map(\.rawValue),
            ["Delegate", "Priority", "Ordinary"],
            "a lane takes the index it is dropped on, pushing the rest along"
        )

        store.moveLane(.delegate, to: 2)
        Check.equal(
            store.lanes.map(\.rawValue),
            ["Priority", "Ordinary", "Delegate"],
            "and can be moved back"
        )

        // The board's context menu offers Move Left on the first column and
        // Move Right on the last; both are disabled, but an out-of-range index
        // must not trap or drop the lane either way.
        store.moveLane(.priority, to: -1)
        Check.equal(store.lanes.first, .priority, "moving past the left edge is a no-op")
        store.moveLane(.delegate, to: 9)
        Check.equal(store.lanes.last, .delegate, "moving past the right edge is a no-op")
        Check.equal(store.lanes.count, 3, "and neither loses a column")

        store.moveLane(Lane("Nowhere"), to: 0)
        Check.equal(store.lanes.count, 3, "moving a lane that isn't on the board changes nothing")

        let reopened = Store(root: root)
        reopened.load()
        store.moveLane(.ordinary, to: 0)
        let after = Store(root: root)
        after.load()
        Check.equal(after.lanes.first, .ordinary, "the chosen order survives a relaunch")
        Check.equal(reopened.lanes.count, 3, "the earlier read saw a full board")
    }

    Check.suite("Lanes — renaming") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let task = TaskItem(label: "Rename with me", lane: .ordinary)
        store.addTask(task)

        store.renameLane(.ordinary, to: "This week")
        Check.equal(store.lanes[1], Lane("This week"), "the lane keeps its position")
        Check.equal(
            store.tasks.first { $0.id == task.id }?.lane,
            Lane("This week"),
            "and its tasks come with it"
        )

        store.renameLane(Lane("This week"), to: "  ")
        Check.equal(store.lanes[1], Lane("This week"), "a blank name is refused")

        // Two columns meaning one lane is something nothing downstream could
        // tell apart, so a rename onto an existing name merges.
        store.renameLane(Lane("This week"), to: "Priority")
        Check.equal(store.lanes.map(\.rawValue), ["Priority", "Delegate"], "renaming onto a name merges")
        Check.equal(
            store.tasks.first { $0.id == task.id }?.lane,
            .priority,
            "and the merged lane's tasks land in the survivor"
        )
    }

    Check.suite("Lanes — deleting keeps the tasks") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let stranded = TaskItem(label: "Don't lose me", lane: .delegate, meta: "Follow up")
        store.addTask(stranded)
        let before = store.tasks.count

        store.deleteLane(.delegate)
        Check.expect(!store.lanes.contains(.delegate), "the column goes")
        Check.equal(
            store.tasks.first { $0.id == stranded.id }?.lane,
            .priority,
            "its tasks fall into the first lane that's left, not into nothing"
        )
        Check.equal(store.tasks.count, before, "nothing is deleted with the column")

        store.deleteLane(.priority)
        store.deleteLane(.ordinary)
        Check.equal(store.lanes.count, 1, "the last lane can't be deleted")
        Check.expect(
            store.tasks.allSatisfy { store.lanes.contains($0.lane) },
            "so every task still has a column to be drawn in"
        )
    }

    Check.suite("Lanes — a task always lands somewhere visible") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        // The calendar's follow-up asks for Delegate by name, and the user may
        // have deleted it since.
        store.deleteLane(.delegate)
        store.addTask(TaskItem(label: "Follow up: standup", lane: .delegate))
        Check.equal(
            store.tasks.last?.lane,
            store.defaultLane,
            "a task naming a deleted lane joins the default column"
        )
        Check.expect(!store.lanes.contains(.delegate), "rather than resurrecting the lane")

        // tasks.json is hand-editable and archives bring their own lanes, so
        // reconciliation has to catch what add-time snapping can't.
        let hand = Store(root: root)
        hand.load()
        Check.expect(
            hand.tasks.allSatisfy { hand.lanes.contains($0.lane) },
            "every lane a task claims is a column after a reload"
        )
    }

    Check.suite("Lanes — a store with no lanes.json") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // What an install from before user-made lanes looks like: tasks naming
        // lowercase enum raw values, and no lane list at all.
        let legacy = """
        [{"createdAt":"2026-08-31T09:00:00Z","done":false,"id":"\(UUID().uuidString)",\
        "label":"From the old format","lane":"waiting","meta":""}]
        """
        try? legacy.write(to: root.appendingPathComponent("tasks.json"), atomically: true, encoding: .utf8)

        let store = Store(root: root)
        store.load()
        Check.expect(store.lanes.contains(Lane("waiting")), "a lane known only to a task joins the board")
        Check.equal(store.lanes.prefix(3).map(\.rawValue), Lane.starters.map(\.rawValue), "after the seeded three")
        Check.equal(store.tasks.count, 1, "and the task is still there")
    }

    Check.suite("Editing a task") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let task = TaskItem(label: "Ship it", lane: .priority, meta: "Due today")
        store.addTask(task)

        store.edit(taskId: task.id, label: "  Ship it properly  ", meta: "  Due Friday  ")
        let edited = store.tasks.first { $0.id == task.id }
        Check.equal(edited?.label, "Ship it properly", "the label is updated and trimmed")
        Check.equal(edited?.meta, "Due Friday", "so is the meta")
        Check.equal(edited?.lane, .priority, "editing text doesn't move the task")

        // The row editor commits when focus leaves, so an emptied field must
        // read as an abandoned edit rather than a nameless task.
        store.edit(taskId: task.id, label: "   ", meta: "ignored")
        Check.equal(
            store.tasks.first { $0.id == task.id }?.label,
            "Ship it properly",
            "a blank label leaves the task alone"
        )
        Check.equal(store.tasks.first { $0.id == task.id }?.meta, "Due Friday", "meta included")

        // Meta is clearable — it is optional on the row.
        store.edit(taskId: task.id, label: "Ship it properly", meta: "")
        Check.equal(store.tasks.first { $0.id == task.id }?.meta, "", "meta can be cleared")

        let count = store.tasks.count
        store.edit(taskId: UUID(), label: "Nobody", meta: "")
        Check.equal(store.tasks.count, count, "editing a task that doesn't exist adds nothing")

        let reopened = Store(root: root)
        reopened.load()
        Check.equal(
            reopened.tasks.first { $0.id == task.id }?.label,
            "Ship it properly",
            "an edit is written through to disk"
        )
    }

    Check.suite("Lanes — the board's order survives export and import") {
        let (source, sourceRoot) = freshStore()
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        source.addLane(named: "Blocked")
        source.moveLane(Lane("Blocked"), to: 0)
        source.addTask(TaskItem(label: "Waiting on infra", lane: Lane("Blocked")))

        let archive = Exporter.archive(from: source)
        Check.equal(archive.lanes?.first, Lane("Blocked"), "the archive carries the column order")

        let (destination, destinationRoot) = freshStore()
        defer { try? FileManager.default.removeItem(at: destinationRoot) }
        destination.replaceAll(with: archive)
        Check.equal(
            destination.lanes.map(\.rawValue),
            ["Blocked", "Priority", "Ordinary", "Delegate"],
            "and an import restores the board as it was"
        )

        // An archive from before lanes were user-made has only what each task
        // names, and the board is rebuilt from that.
        let old = Archive(
            notes: [],
            folders: nil,
            lanes: nil,
            tasks: [TaskItem(label: "Old one", lane: Lane("waiting"))],
            log: [],
            milestones: []
        )
        destination.replaceAll(with: old)
        Check.expect(destination.lanes.contains(Lane("waiting")), "an old archive's lane is recovered from its tasks")
        Check.expect(
            destination.tasks.allSatisfy { destination.lanes.contains($0.lane) },
            "leaving no task without a column"
        )
    }

    Check.suite("Lanes — tasks.md follows the board") {
        let tasks = [
            TaskItem(label: "Waiting on infra", lane: Lane("Blocked")),
            TaskItem(label: "Ship it", lane: .priority),
        ]
        let ordered = Exporter.tasksMarkdown(tasks, lanes: [.priority, Lane("Blocked")])
        Check.expect(
            ordered.range(of: "## Priority")!.lowerBound < ordered.range(of: "## Blocked")!.lowerBound,
            "sections follow the board's column order, not the tasks' order"
        )

        // Callers with only tasks — an archive from before lanes were stored —
        // still get every lane, in the order the tasks name them.
        let fallback = Exporter.tasksMarkdown(tasks)
        Check.expect(fallback.contains("## Blocked"), "a lane the app never shipped is still exported")
        Check.expect(
            fallback.range(of: "## Blocked")!.lowerBound < fallback.range(of: "## Priority")!.lowerBound,
            "falling back to first-appearance order"
        )
    }
}
