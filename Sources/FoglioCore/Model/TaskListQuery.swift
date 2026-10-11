import Foundation

enum TaskStatus: String, CaseIterable, Identifiable {
    case open, completed, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .open: "Open"
        case .completed: "Completed"
        case .all: "All"
        }
    }
}

enum TaskListQuery {
    /// Counts use the same list and search scope as the visible rows.
    static func counts(_ tasks: [TaskItem], list: Lane?, search: String) -> [TaskStatus: Int] {
        let matches = filtered(tasks, status: .all, list: list, search: search)
        let completed = matches.filter(\.done).count
        return [.open: matches.count - completed, .completed: completed, .all: matches.count]
    }

    static func filtered(_ tasks: [TaskItem], status: TaskStatus, list: Lane?, search: String, preservingOrder: Bool = false) -> [TaskItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = tasks.filter { task in
            (status == .all || task.done == (status == .completed))
                && (list == nil || task.lane == list)
                && task.matches(query)
        }
        if preservingOrder { return matches }
        return matches.sorted { lhs, rhs in
            if lhs.done != rhs.done { return !lhs.done }
            let left = lhs.done ? (lhs.completedAt ?? lhs.createdAt) : lhs.createdAt
            let right = rhs.done ? (rhs.completedAt ?? rhs.createdAt) : rhs.createdAt
            return left > right
        }
    }
}
