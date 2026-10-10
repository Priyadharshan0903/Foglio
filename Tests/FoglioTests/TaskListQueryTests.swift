import Foundation
@testable import FoglioCore

func taskListQueryTests() {
    Check.suite("Task lists — status, search and completion history") {
        let old = Date(timeIntervalSince1970: 100)
        let recent = Date(timeIntervalSince1970: 200)
        let open = TaskItem(label: "Write release notes", lane: .ordinary, meta: "Draft ✨", createdAt: recent)
        let completed = TaskItem(label: "Ship version one", lane: .priority, done: true, completedAt: old)
        let newer = TaskItem(label: "Ship version two", lane: .ordinary, done: true, completedAt: recent)
        let tasks = [completed, open, newer]
        Check.equal(TaskListQuery.filtered(tasks, status: .open, list: nil, search: ""), [open], "Open excludes completions")
        Check.equal(TaskListQuery.filtered(tasks, status: .completed, list: nil, search: ""), [newer, completed],
                    "Completed includes older days and sorts newest first")
        Check.equal(TaskListQuery.filtered(tasks, status: .all, list: nil, search: ""), [open, newer, completed],
                    "All keeps open tasks above completed ones")
        Check.equal(TaskListQuery.filtered(tasks, status: .all, list: .priority, search: ""), [completed], "list filter scopes results")
        Check.equal(TaskListQuery.filtered(tasks, status: .open, list: nil, search: " DRAFT "), [open], "search checks details and trims spaces")
        Check.equal(TaskListQuery.filtered(tasks, status: .all, list: .priority, search: "notes"), [], "search and list filters combine")
        Check.equal(TaskListQuery.counts(tasks, list: nil, search: ""), [.open: 1, .completed: 2, .all: 3],
                    "status counts include every task in the current scope")
        Check.equal(TaskListQuery.counts(tasks, list: .priority, search: "SHIP"), [.open: 0, .completed: 1, .all: 1],
                    "status counts respect list and search filters")
        Check.equal(TaskListQuery.counts(tasks, list: .priority, search: "notes"), [.open: 0, .completed: 0, .all: 0],
                    "an empty search result shows zero in every filter")
    }
}
