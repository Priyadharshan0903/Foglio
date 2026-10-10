import Foundation

/// Names can change without changing a task's column identity. Categories
/// retain completion semantics independently of the visible status name.
struct TaskBoardStatus: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    let category: TaskWorkflow
    var label: String { name }
    var symbol: String { category.symbol }
    static let starters: [TaskBoardStatus] = TaskWorkflow.allCases.map {
        TaskBoardStatus(id: $0 == .inProgress ? "in_progress" : $0.rawValue, name: $0.label, category: $0)
    }
}

struct TaskWorkspace: Codable, Equatable {
    var statuses: [TaskBoardStatus] = TaskBoardStatus.starters
    var lastTicketNumber: Int = 0
}

enum TaskWorkspaceError: LocalizedError {
    case invalidName, duplicateName, tooManyStatuses, missingStatus, invalidPosition
    var errorDescription: String? {
        switch self {
        case .invalidName: "Use a status name with 1–80 characters on a single line."
        case .duplicateName: "A status with this name already exists."
        case .tooManyStatuses: "You can have up to 20 statuses."
        case .missingStatus: "This status no longer exists."
        case .invalidPosition: "Choose a position within the status list."
        }
    }
}

enum TaskSort: String, CaseIterable, Identifiable {
    case newest, oldest, priority, dueDate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .priority: "Priority"
        case .dueDate: "Due date"
        }
    }
    func ordered(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { a, b in
            switch self {
            case .priority:
                let left = a.taskPriority == .none ? 5 : a.taskPriority.rawValue
                let right = b.taskPriority == .none ? 5 : b.taskPriority.rawValue
                if left != right { return left < right }
            case .dueDate:
                if a.dueDate != b.dueDate { return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) }
            case .oldest:
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            case .newest: break
            }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
