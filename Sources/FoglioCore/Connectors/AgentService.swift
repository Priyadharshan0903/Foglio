import Foundation
import CryptoKit
import FoglioConnectorKit

enum AgentRevision {
    static func of<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: (try? encoder.encode(value)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    static func date(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    static func parse(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text) else { throw ConnectorError("invalid_date", "Use an ISO 8601 date-time with a timezone offset.") }
        return date
    }
}

struct AgentEvent: Encodable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String
    let notes: String
    let calendarID: String?
    let calendarName: String
    let organizer: String
    let attendees: [String]
    let writable: Bool
    let revision: String
    var json: JSON {
        ["id": .string(id), "title": .string(title), "start": .string(AgentRevision.date(start)),
         "end": .string(AgentRevision.date(end)), "location": .string(location), "notes": .string(notes),
         "calendar_id": calendarID.map(JSON.string) ?? .null, "calendar": .string(calendarName),
         "organizer": .string(organizer), "attendees": .array(attendees.map(JSON.string)),
         "writable": .bool(writable), "revision": .string(revision)]
    }
}

@MainActor
protocol AgentCalendarProviding: AnyObject {
    var connectorInfo: JSON { get }
    var connectorRange: DateInterval { get }
    func connectorCalendars() throws -> [JSON]
    func connectorEvents(in range: DateInterval) async throws -> [AgentEvent]
    func connectorEvent(id: String, date: Date?) async throws -> AgentEvent
    func connectorCreateEvent(fields: [String: JSON]) throws -> AgentEvent
    func connectorUpdateEvent(id: String, revision: String, fields: [String: JSON]) throws -> AgentEvent
}

/// All requests use the app's live Store on the main actor. The stdio process
/// never opens the library itself, so it cannot race an autosave or app write.
@MainActor
final class AgentService {
    private let store: Store
    private let calendar: AgentCalendarProviding
    private let enabled: () -> Bool
    private let allowEdits: () -> Bool
    private let autoLog: () -> Bool
    init(store: Store, calendar: AgentCalendarProviding, enabled: @escaping () -> Bool,
         allowEdits: @escaping () -> Bool, autoLog: @escaping () -> Bool = { true }) {
        self.store = store; self.calendar = calendar; self.enabled = enabled
        self.allowEdits = allowEdits; self.autoLog = autoLog
    }

    func call(_ name: String, arguments: JSON) async throws -> JSON {
        guard enabled() else { throw ConnectorError("disabled", "Enable Agent connections in Foglio Settings.") }
        guard let tool = ToolCatalog.find(name) else { throw ConnectorError("unknown_tool", "Unknown Foglio tool.") }
        let a = try tool.validate(arguments)
        if !tool.readOnly { try requireEdits() }
        switch name {
        case "foglio_status":
            return ["connected": true, "allow_edits": .bool(allowEdits()), "calendar": calendar.connectorInfo,
                    "notes": .number(Double(store.notes.count)), "tasks": .number(Double(store.tasks.count))]
        case "task_lists": return ["lists": .array(store.lanes.map { lane in
            ["id": .string(lane.id), "name": .string(lane.label), "count": .number(Double(store.tasks.filter { $0.lane == lane }.count))]
        })]
        case "task_list_create":
            let name = try nonempty(a, "name")
            try beginWrite()
            guard let lane = store.addLane(named: name) else { throw ConnectorError("invalid_name", "Give the list a name.") }
            try finishWrite(); return ["id": .string(lane.id), "name": .string(lane.label)]
        case "task_statuses": return ["statuses": .array(store.statuses.enumerated().map { statusJSON($0.element, position: $0.offset) })]
        case "task_status_create":
            let name = try nonempty(a, "name"), category = try workflowCategory(a["category"]!.string!)
            try beginWrite()
            let created: TaskBoardStatus
            do { created = try store.addStatus(name: name, category: category) }
            catch { throw ConnectorError("invalid_arguments", error.localizedDescription) }
            try finishWrite(); return statusJSON(created, position: store.statuses.firstIndex(of: created)!)
        case "task_status_update":
            try checkRevision(a, AgentRevision.of(store.statuses))
            guard a["name"] != nil || a["position"] != nil else { throw ConnectorError("invalid_arguments", "Supply a name or position.") }
            let name = try a["name"].map { _ in try nonempty(a, "name") }
            let id = a["id"]!.string!
            try beginWrite()
            do { try store.updateStatus(id: id, name: name, position: a["position"]?.number.map(Int.init)) }
            catch { throw ConnectorError("invalid_arguments", error.localizedDescription) }
            try finishWrite()
            let index = store.statuses.firstIndex { $0.id == id }!
            return statusJSON(store.statuses[index], position: index)
        case "tasks_list":
            let lane = try a["list"].map { try list($0.string!) }
            let status = try a["status"].map { try workflow($0.string!) }
            let query = a["query"]?.string ?? ""
            let tasks = store.tasks.filter { task in
                (lane == nil || task.lane == lane) && (status == nil || store.status(for: task).id == status?.id)
                && task.matches(query)
                && (a["project"] == nil || task.project?.caseInsensitiveCompare(a["project"]!.string!) == .orderedSame)
                && (a["priority"] == nil || task.taskPriority.rawValue == Int(a["priority"]!.number!))
            }
            return page(tasks.map(taskJSON), key: "tasks", a)
        case "task_get": return try taskJSON(task(a))
        case "task_create":
            let title = try nonempty(a, "title")
            let lane = try a["list"].map { try list($0.string!) } ?? store.defaultLane
            let status = try a["status"].map { try workflow($0.string!) } ?? workflow("todo")
            var task = TaskItem(label: title, lane: lane, meta: a["description"]?.string ?? "")
            try applyProperties(a, to: &task)
            try beginWrite(); store.addTask(task); store.setStatus(taskId: task.id, statusID: status.id, autoLog: autoLog())
            try finishWrite(); return taskJSON(store.tasks.first { $0.id == task.id }!)
        case "task_update", "task_move":
            let current = try task(a)
            try checkRevision(a, AgentRevision.of(current))
            guard !store.editingTaskIds.contains(current.id) else { throw ConnectorError("resource_busy", "This task's editor is open. Save or close it in Foglio before an agent edits it.") }
            let lane = try a["list"].map { try list($0.string!) }
            let status = try a["status"].map { try workflow($0.string!) }
            let title = try a["title"].map { _ in try nonempty(a, "title") } ?? current.label
            guard a.keys.contains(where: { !["id", "revision"].contains($0) }) else { throw ConnectorError("invalid_arguments", "Supply a field to change.") }
            var updated = current
            if name == "task_update" {
                updated.label = title; updated.meta = a["description"]?.string ?? current.meta
                try applyProperties(a, to: &updated)
            }
            try beginWrite()
            if name == "task_update" { store.update(updated) }
            if let lane { store.move(taskId: current.id, to: lane) }
            if let status { store.setStatus(taskId: current.id, statusID: status.id, autoLog: autoLog()) }
            try finishWrite(); return taskJSON(store.tasks.first { $0.id == current.id }!)
        case "note_folders": return ["folders": .array(store.folders.map { folder in
            ["id": .string(folder.id), "name": .string(folder.label), "count": .number(Double(store.notes.filter { $0.folder == folder }.count))]
        })]
        case "note_folder_create":
            let name = try nonempty(a, "name"); try beginWrite()
            guard let folder = store.addFolder(named: name) else { throw ConnectorError("invalid_name", "Give the folder a name.") }
            try finishWrite(); return ["id": .string(folder.id), "name": .string(folder.label)]
        case "notes_list":
            let folder = try a["folder"].map { try self.folder($0.string!) }
            let query = a["query"]?.string ?? ""
            return page(store.notes.filter { (folder == nil || $0.folder == folder) && $0.matches(query) }
                .map { noteJSON($0, full: false) }, key: "notes", a)
        case "note_get": return try noteJSON(note(a))
        case "note_create":
            let note = Note(title: try nonempty(a, "title"), body: a["body"]?.string ?? "",
                            folder: try a["folder"].map { try folder($0.string!) } ?? .scratch)
            try beginWrite(); store.upsert(note); try finishWrite(); return noteJSON(store.note(id: note.id)!)
        case "note_update", "note_move":
            var current = try note(a); try checkRevision(a, AgentRevision.of(current))
            let destination = try a["folder"].map { try folder($0.string!) }
            if let title = a["title"] { current.title = try nonempty(["title": title], "title") }
            if let body = a["body"]?.string { current.body = body }
            guard a.keys.contains(where: { !["id", "revision"].contains($0) }) else { throw ConnectorError("invalid_arguments", "Supply a field to change.") }
            try beginWrite()
            if let destination { store.move(noteIds: [current.id], to: destination) }
            else { store.upsert(current) }
            try finishWrite(); return noteJSON(store.note(id: current.id)!)
        case "calendar_list": return ["source": calendar.connectorInfo, "calendars": .array(try calendar.connectorCalendars())]
        case "calendar_events":
            let range = try eventRange(a)
            let events = try await calendar.connectorEvents(in: range)
            try requireConnection()
            let query = a["query"]?.string ?? ""
            return page(events.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) }.map(\.json), key: "events", a)
        case "calendar_event_get":
            let event = try await calendar.connectorEvent(id: a["id"]!.string!, date: try a["date"].map { try AgentRevision.parse($0.string!) })
            try requireConnection(); return event.json
        case "calendar_event_create":
            _ = try nonempty(a, "title"); try validateEventDates(a)
            return try calendar.connectorCreateEvent(fields: a).json
        case "calendar_event_update", "calendar_event_move":
            guard a.keys.contains(where: { !["id", "revision"].contains($0) }) else { throw ConnectorError("invalid_arguments", "Supply a field to change.") }
            if a["title"] != nil { _ = try nonempty(a, "title") }
            try validateEventDates(a)
            return try calendar.connectorUpdateEvent(id: a["id"]!.string!, revision: a["revision"]!.string!, fields: a).json
        case "meeting_note_create", "meeting_task_create":
            let event = try await calendar.connectorEvent(id: a["event_id"]!.string!, date: try a["date"].map { try AgentRevision.parse($0.string!) })
            let when = DateFormatter.localizedString(from: event.start, dateStyle: .medium, timeStyle: .short)
            if name == "meeting_note_create" {
                let folder = try a["folder"].map { try self.folder($0.string!) } ?? .scratch
                let body = "# \(event.title)\n\n\(when) · \(event.calendarName)\n\n## Notes\n\n" + (a["body"]?.string ?? "")
                let title = String(event.title.components(separatedBy: .newlines).joined(separator: " ").prefix(400))
                let note = Note(title: title, body: body, folder: folder, pin: "Meeting: \(title)", sourceEventID: event.id)
                try beginWrite(); store.upsert(note); try finishWrite(); return noteJSON(store.note(id: note.id)!)
            }
            let task = TaskItem(label: try nonempty(a, "title"), lane: try a["list"].map { try list($0.string!) } ?? store.defaultLane,
                                meta: "Follow-up from \(event.title)\n\(when) · \(event.calendarName)", sourceEventID: event.id)
            try beginWrite(); store.addTask(task); try finishWrite(); return taskJSON(store.tasks.first { $0.id == task.id }!)
        default: throw ConnectorError("unknown_tool", "Unknown Foglio tool.")
        }
    }
    private func requireConnection() throws {
        guard enabled() else { throw ConnectorError("disabled", "Agent connections were disabled while this request was running.") }
    }
    private func requireEdits() throws {
        try requireConnection()
        guard allowEdits() else { throw ConnectorError("read_only", "Enable Allow agents to make changes in Foglio Settings to use this tool.") }
    }
    private func beginWrite() throws { try requireEdits(); store.clearPersistenceError(); store.flushPendingSaves(); try finishWrite() }
    private func finishWrite() throws {
        if store.persistenceError != nil { throw ConnectorError("save_failed", "Foglio could not save to disk. An edit may still appear in memory; check storage access in the app before retrying.") }
    }
    private func nonempty(_ a: [String: JSON], _ key: String) throws -> String {
        let value = (a[key]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .newlines) == nil else {
            throw ConnectorError("invalid_arguments", "\(key) must be a non-empty, single-line value.")
        }
        return value
    }
    private func task(_ a: [String: JSON]) throws -> TaskItem {
        let raw = a["id"]?.string ?? ""
        guard let task = store.tasks.first(where: { $0.id.uuidString.caseInsensitiveCompare(raw) == .orderedSame || (!$0.ticketID.isEmpty && $0.ticketID.caseInsensitiveCompare(raw) == .orderedSame) }) else { throw ConnectorError("not_found", "Task not found.") }; return task
    }
    private func note(_ a: [String: JSON]) throws -> Note {
        guard let id = UUID(uuidString: a["id"]?.string ?? ""), let note = store.note(id: id) else { throw ConnectorError("not_found", "Note not found or is in Trash.") }; return note
    }
    private func folder(_ name: String) throws -> Folder {
        guard let value = store.folders.first(where: { $0.id == name.lowercased() }) else { throw ConnectorError("not_found", "Folder not found. Use note_folders or note_folder_create first.") }; return value
    }
    private func list(_ name: String) throws -> Lane {
        guard let value = store.lanes.first(where: { $0.id == name.lowercased() }) else { throw ConnectorError("not_found", "Task list not found. Use task_lists or task_list_create first.") }; return value
    }
    private func workflow(_ raw: String) throws -> TaskBoardStatus {
        let id = raw == "inProgress" ? "in_progress" : raw
        guard let value = store.statuses.first(where: { $0.id == id }) else { throw ConnectorError("invalid_status", "Unknown status. Call task_statuses first.") }
        return value
    }
    private func workflowCategory(_ raw: String) throws -> TaskWorkflow {
        guard let value = TaskWorkflow(rawValue: raw == "in_progress" ? "inProgress" : raw) else { throw ConnectorError("invalid_status", "Invalid category.") }
        return value
    }
    private func statusJSON(_ status: TaskBoardStatus, position: Int) -> JSON {
        ["id": .string(status.id), "name": .string(status.name),
         "category": .string(status.category == .inProgress ? "in_progress" : status.category.rawValue),
         "position": .number(Double(position)), "revision": .string(AgentRevision.of(store.statuses))]
    }
    private func applyProperties(_ a: [String: JSON], to task: inout TaskItem) throws {
        if let p = a["priority"]?.number { task.priority = TaskPriority(rawValue: Int(p)) }
        for key in ["project", "assignee"] {
            if let raw = a[key]?.string {
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.rangeOfCharacter(from: .newlines) == nil else { throw ConnectorError("invalid_arguments", "\(key) must be a single-line value.") }
                if key == "project" { task.project = text.isEmpty ? nil : text }
                else { task.assignee = text.isEmpty ? nil : text }
            }
        }
        if let items = a["labels"]?.array {
            var seen = Set<String>(), labels: [String] = []
            for item in items {
                let label = try nonempty(["label": item], "label")
                if seen.insert(label.lowercased()).inserted { labels.append(label) }
            }
            task.labels = labels
        }
        if let raw = a["due_date"]?.string { task.dueDate = raw.isEmpty ? nil : try AgentRevision.parse(raw) }
        if let value = a["estimate"]?.number { task.estimate = value == 0 ? nil : Int(value) }
        if let parent = a["parent_id"]?.string { task.parentID = parent.isEmpty ? nil : try self.task(["id": .string(parent)]).id }
        if let items = a["blocked_by"]?.array {
            var seen = Set<UUID>()
            task.blockedBy = try items.map { try self.task(["id": $0]).id }.filter { seen.insert($0).inserted }
        }
        do { try TaskRelations.validate(task, among: store.tasks) }
        catch { throw ConnectorError("invalid_relation", error.localizedDescription) }
    }
    private func checkRevision(_ a: [String: JSON], _ revision: String) throws {
        guard a["revision"]?.string == revision else { throw ConnectorError("conflict", "This item changed after it was read. Get it again and apply your edit to the current content.") }
    }
    private func page(_ values: [JSON], key: String, _ a: [String: JSON]) -> JSON {
        let offset = Int(a["offset"]?.number ?? 0), limit = Int(a["limit"]?.number ?? 50)
        let end = min(values.count, offset + limit)
        return .object([key: .array(Array(values.dropFirst(offset).prefix(limit))), "total": .number(Double(values.count)),
                        "next_offset": end < values.count ? .number(Double(end)) : .null])
    }
    private func taskJSON(_ task: TaskItem) -> JSON {
        ["id": .string(task.id.uuidString), "title": .string(task.label), "description": .string(task.meta),
         "ticket_id": .string(task.ticketID), "list": .string(task.lane.id), "status": .string(store.status(for: task).id),
         "status_name": .string(store.status(for: task).name),
         "priority": .number(Double(task.taskPriority.rawValue)), "priority_name": .string(task.taskPriority.label),
         "project": task.project.map(JSON.string) ?? .null, "assignee": task.assignee.map(JSON.string) ?? .null,
         "labels": .array((task.labels ?? []).map(JSON.string)),
         "due_date": task.dueDate.map { .string(AgentRevision.date($0)) } ?? .null,
         "estimate": task.estimate.map { .number(Double($0)) } ?? .null,
         "parent_id": task.parentID.map { .string($0.uuidString) } ?? .null,
         "blocked_by": .array((task.blockedBy ?? []).map { .string($0.uuidString) }),
         "subtask_ids": .array(store.tasks.filter { $0.parentID == task.id }.map { .string($0.id.uuidString) }),
         "is_blocked": .bool(store.tasks.contains { (task.blockedBy ?? []).contains($0.id) && !$0.done }),
         "created_at": .string(AgentRevision.date(task.createdAt)), "completed_at": task.completedAt.map { .string(AgentRevision.date($0)) } ?? .null,
         "event_id": task.sourceEventID.map(JSON.string) ?? .null,
         "revision": .string(AgentRevision.of(task))]
    }
    private func noteJSON(_ note: Note, full: Bool = true) -> JSON {
        var result: [String: JSON] = ["id": .string(note.id.uuidString), "title": .string(note.title), "folder": .string(note.folder.id),
                                    "updated_at": .string(AgentRevision.date(note.updatedAt)), "revision": .string(AgentRevision.of(note)),
                                    "linked_to": note.pin.map(JSON.string) ?? .null]
        result["event_id"] = note.sourceEventID.map(JSON.string) ?? .null
        if full { result["body"] = .string(note.body) } else { result["snippet"] = .string(String(note.snippet.prefix(160))) }
        return .object(result)
    }
    private func eventRange(_ a: [String: JSON]) throws -> DateInterval {
        if a["start"] == nil && a["end"] == nil { return calendar.connectorRange }
        guard let start = a["start"]?.string, let end = a["end"]?.string else { throw ConnectorError("invalid_arguments", "Supply both start and end.") }
        let from = try AgentRevision.parse(start), to = try AgentRevision.parse(end)
        guard to > from, to.timeIntervalSince(from) <= 92 * 86400 else { throw ConnectorError("invalid_range", "Choose a positive range of at most 92 days.") }
        return DateInterval(start: from, end: to)
    }
    private func validateEventDates(_ a: [String: JSON]) throws {
        let from = try a["start"].map { try AgentRevision.parse($0.string!) }, to = try a["end"].map { try AgentRevision.parse($0.string!) }
        if let from, let to, to <= from { throw ConnectorError("invalid_range", "Event end must be after its start.") }
    }
}
