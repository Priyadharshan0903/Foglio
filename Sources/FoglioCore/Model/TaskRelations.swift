import Foundation

enum TaskRelationError: LocalizedError {
    case missingTask, selfReference, cycle
    var errorDescription: String? {
        switch self {
        case .missingTask: "A related task no longer exists."
        case .selfReference: "A task cannot be its own parent or blocker."
        case .cycle: "This relation would create a circular task hierarchy or dependency."
        }
    }
}

enum TaskRelations {
    static func validate(_ draft: TaskItem, among tasks: [TaskItem]) throws {
        let related = (draft.blockedBy ?? []) + (draft.parentID.map { [$0] } ?? [])
        guard !related.contains(draft.id) else { throw TaskRelationError.selfReference }
        guard related.allSatisfy({ id in tasks.contains { $0.id == id } }) else { throw TaskRelationError.missingTask }
        let values = tasks.filter { $0.id != draft.id } + [draft]
        let byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func reachesSelf(_ id: UUID, parents: Bool, visited: inout Set<UUID>) -> Bool {
            if id == draft.id { return true }
            guard visited.insert(id).inserted, let task = byID[id] else { return false }
            let links = parents ? (task.parentID.map { [$0] } ?? []) : (task.blockedBy ?? [])
            return links.contains { reachesSelf($0, parents: parents, visited: &visited) }
        }
        for parents in [true, false] {
            var visited = Set<UUID>()
            let links = parents ? (draft.parentID.map { [$0] } ?? []) : (draft.blockedBy ?? [])
            if links.contains(where: { reachesSelf($0, parents: parents, visited: &visited) }) { throw TaskRelationError.cycle }
        }
    }
}
