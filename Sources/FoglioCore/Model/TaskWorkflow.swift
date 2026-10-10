import Foundation

enum TaskWorkflow: String, Codable, CaseIterable, Identifiable {
    case backlog, todo, inProgress, done
    var id: String { rawValue }
    var label: String {
        switch self {
        case .backlog: "Backlog"
        case .todo: "To do"
        case .inProgress: "In progress"
        case .done: "Done"
        }
    }
    var symbol: String {
        switch self {
        case .backlog: "circle.dashed"
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }
}

enum TaskLayout: String { case board, list }

extension TaskItem {
    /// Old files had only `done`. A missing workflow becomes To do or Done.
    var workflowStatus: TaskWorkflow { done ? .done : (workflow == .done ? .todo : workflow ?? .todo) }
}
