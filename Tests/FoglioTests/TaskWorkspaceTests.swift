import Foundation
@testable import FoglioCore

@MainActor
func taskWorkspaceTests() {
    func fresh() -> (Store, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foglio-workflow-\(UUID())")
        let store = Store(root: root); store.load()
        return (store, root)
    }
    Check.suite("Ticket IDs — migration, restart, deletion, and import") {
        let (store, root) = fresh()
        defer { try? FileManager.default.removeItem(at: root) }
        let older = TaskItem(label: "Legacy title", meta: "Project: Legacy\n- [ ] Keep this", createdAt: Date(timeIntervalSince1970: 1))
        let newer = TaskItem(label: "Later task", createdAt: Date(timeIntervalSince1970: 2))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try! encoder.encode([newer, older]).write(to: root.appendingPathComponent("tasks.json"))
        let migrated = Store(root: root); migrated.load()
        let first = migrated.tasks.first { $0.id == older.id }!
        Check.equal(first.ticketID, "FOG-1", "older tasks receive earlier ticket numbers")
        Check.equal(first.label, older.label, "migration never rewrites titles")
        Check.equal(first.meta, older.meta, "migration never rewrites Markdown")
        Check.equal(migrated.tasks.first { $0.id == newer.id }?.ticketID, "FOG-2", "legacy tasks receive unique numbers")
        let reload = Store(root: root); reload.load()
        Check.equal(reload.tasks.first { $0.id == older.id }?.ticketID, first.ticketID, "IDs stay stable after restarting")
        reload.deleteTask(id: newer.id)
        let third = TaskItem(label: "New task"); reload.addTask(third)
        Check.equal(reload.tasks.last?.ticketID, "FOG-3", "deleting the highest ticket does not reuse its number")
        var edited = reload.tasks.last!; edited.ticketNumber = 99; edited.label = "Renamed"
        reload.update(edited)
        Check.equal(reload.tasks.last?.ticketID, "FOG-3", "editing cannot change a ticket number")
        reload.addTask(edited)
        Check.equal(reload.tasks.count, 2, "adding an existing UUID does not duplicate it")
        let archive = Exporter.archive(from: reload)
        Check.equal(archive.taskWorkspace?.lastTicketNumber, 3, "archive preserves the allocation high-water mark")
        reload.replaceAll(with: Archive(tasks: [older]))
        Check.equal(reload.tasks.first?.ticketID, "FOG-4", "importing older data does not reuse a issued number")
        Check.expect(reload.tasks.first?.matches("FOG-4") == true, "ticket IDs are searchable")
        Check.equal(store.tasks.count, 0, "migration fixtures do not affect other in-memory stores")
    }
    Check.suite("Statuses — stable identity, categories, completion, and export") {
        let (store, root) = fresh()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let blocked = try store.addStatus(name: "Blocked", category: .inProgress)
            let shipped = try store.addStatus(name: "Shipped", category: .done)
            let task = TaskItem(label: "A task", priority: .high, project: "Studio", assignee: "Me", labels: ["Release"], dueDate: Date(timeIntervalSince1970: 99999), estimate: 3)
            store.addTask(task)
            store.setStatus(taskId: task.id, statusID: blocked.id, autoLog: true)
            try store.updateStatus(id: blocked.id, name: "Waiting on review", position: 0)
            let current = store.tasks.last!
            Check.equal(store.status(for: current).id, blocked.id, "renaming keeps task status identity")
            Check.equal(store.status(for: current).name, "Waiting on review", "renaming updates the displayed name")
            Check.equal(store.statuses.first?.id, blocked.id, "reordering changes board order")
            Check.expect(!current.done, "an active category remains open")
            let logCount = store.log.count
            store.setStatus(taskId: task.id, statusID: shipped.id, autoLog: true)
            store.setStatus(taskId: task.id, statusID: shipped.id, autoLog: true)
            Check.expect(store.tasks.last!.done, "a custom Done category completes a task")
            Check.equal(store.log.count, logCount + 1, "repeat moves to a completed category log once")
            store.setStatus(taskId: task.id, statusID: blocked.id, autoLog: false)
            Check.expect(store.tasks.last!.completedAt == nil, "reopening clears the completion date")
            store.setDone(taskId: task.id, done: true, autoLog: false)
            Check.equal(store.tasks.last?.statusID, "done", "the ordinary completion action uses the Done identity")
            store.setDone(taskId: task.id, done: false, autoLog: false)
            Check.equal(store.status(for: store.tasks.last!).id, "todo", "ordinary reopening puts a task in To do")
            store.setStatus(taskId: task.id, statusID: blocked.id, autoLog: false)
            let reloaded = Store(root: root); reloaded.load()
            Check.equal(reloaded.statuses, store.statuses, "status names and ordering survive relaunch")
            Check.equal(reloaded.tasks.last?.estimate, 3, "task properties survive relaunch")
            Check.equal(reloaded.tasks.last?.labels, ["Release"], "labels survive relaunch")
            let archive = Exporter.archive(from: store)
            let (destination, targetRoot) = fresh()
            defer { try? FileManager.default.removeItem(at: targetRoot) }
            destination.replaceAll(with: archive)
            Check.equal(destination.statuses, store.statuses, "export/import preserves custom workflow")
            Check.equal(destination.tasks.last?.project, "Studio", "export/import preserves structured task properties")
            Check.expect(Exporter.tasksMarkdown(store.tasks).contains("Priority: High"), "readable export includes task priority")
            Check.expect(Exporter.tasksMarkdown(store.tasks).contains("Project: Studio"), "readable export includes project metadata")
            Check.expect(Exporter.tasksMarkdown(store.tasks, statuses: store.statuses).contains("Waiting on review"), "readable export uses the custom status name")
            Check.expect(Exporter.tasksMarkdown(store.tasks).contains(store.tasks.last!.ticketID), "readable export includes ticket IDs")
            for name in ["", "To do", "waiting ON REVIEW", "Bad\nName"] {
                do { _ = try store.addStatus(name: name, category: .todo); Check.expect(false, "invalid names must fail") }
                catch { Check.expect(true, "empty, duplicate, and multiline names are rejected") }
            }
            let before = store.statuses
            do { try store.updateStatus(id: blocked.id, name: "Changed", position: 999); Check.expect(false, "bad position must fail") }
            catch { Check.equal(store.statuses, before, "invalid update leaves statuses intact") }
        } catch { Check.expect(false, "workflow check failed: \(error)") }
    }
    Check.suite("Task relations — hierarchy, dependencies, cycles, and deletion") {
        let (store, root) = fresh()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = TaskItem(label: "Release")
        store.addTask(parent)
        let child = TaskItem(label: "Review", parentID: parent.id)
        store.addTask(child)
        let follow = TaskItem(label: "Publish", blockedBy: [child.id])
        store.addTask(follow)
        var invalid = store.tasks.first { $0.id == parent.id }!
        invalid.parentID = child.id
        do { try TaskRelations.validate(invalid, among: store.tasks); Check.expect(false, "parent cycle must fail") }
        catch { Check.expect(true, "parent cycles are rejected") }
        invalid = store.tasks.first { $0.id == child.id }!; invalid.blockedBy = [follow.id]
        do { try TaskRelations.validate(invalid, among: store.tasks); Check.expect(false, "dependency cycle must fail") }
        catch { Check.expect(true, "dependency cycles are rejected") }
        invalid.blockedBy = [child.id]
        do { try TaskRelations.validate(invalid, among: store.tasks); Check.expect(false, "self link must fail") }
        catch { Check.expect(true, "self references are rejected") }
        invalid.blockedBy = [UUID()]
        do { try TaskRelations.validate(invalid, among: store.tasks); Check.expect(false, "missing link must fail") }
        catch { Check.expect(true, "missing tasks are rejected") }
        let reloaded = Store(root: root); reloaded.load()
        Check.equal(reloaded.tasks.first { $0.id == child.id }?.parentID, parent.id, "subtask parent survives restart")
        Check.equal(reloaded.tasks.first { $0.id == follow.id }?.blockedBy, [child.id], "dependencies survive restart")
        store.deleteTask(id: parent.id)
        Check.expect(store.tasks.first { $0.id == child.id }?.parentID == nil, "deleting a parent preserves and detaches its child")
        store.deleteTask(id: child.id)
        Check.equal(store.tasks.first { $0.id == follow.id }?.blockedBy, [], "deleting a blocker clears its links")
    }
    Check.suite("Ticket allocation — persistence failure") {
        let (store, root) = fresh()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("task-workspace.json")
        try! FileManager.default.removeItem(at: path)
        try! FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        store.addTask(TaskItem(label: "Should not appear"))
        Check.equal(store.tasks.count, 0, "a failed reservation cannot create an unpersisted ticket")
        Check.expect(store.persistenceError != nil, "allocation failures are visible")
    }
    Check.suite("Task properties — search and ordering") {
        let older = TaskItem(label: "Older", createdAt: Date(timeIntervalSince1970: 1), priority: .urgent, project: "Studio", labels: ["Backend"], dueDate: Date(timeIntervalSince1970: 20))
        let newer = TaskItem(label: "Newer", createdAt: Date(timeIntervalSince1970: 2))
        Check.equal(TaskListQuery.filtered([older, newer], status: .all, list: nil, search: "backend").map(\.id), [older.id], "labels are searchable")
        Check.equal(TaskListQuery.filtered([older, newer], status: .all, list: nil, search: "studio").map(\.id), [older.id], "projects are searchable")
        Check.equal(TaskSort.priority.ordered([newer, older]).first?.id, older.id, "urgent work sorts above unset priority")
        Check.equal(TaskSort.dueDate.ordered([newer, older]).first?.id, older.id, "dated work sorts above undated work")
        Check.equal(TaskSort.oldest.ordered([newer, older]).first?.id, older.id, "oldest ordering is available")
    }
}
