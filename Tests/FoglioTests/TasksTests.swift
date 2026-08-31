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
