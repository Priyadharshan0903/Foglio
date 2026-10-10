import Foundation

public struct ConnectorTool {
    public let name: String
    public let description: String
    public let properties: [String: JSON]
    public let required: [String]
    public let readOnly: Bool
    public var json: JSON {
        ["name": .string(name), "description": .string(description),
         "inputSchema": ["type": "object", "properties": .object(properties),
                         "required": .array(required.map(JSON.string)), "additionalProperties": false],
         "annotations": ["readOnlyHint": .bool(readOnly), "destructiveHint": .bool(!readOnly && !name.hasSuffix("_create")),
                         "openWorldHint": .bool(name.hasPrefix("calendar_") || name.hasPrefix("meeting_"))]]
    }
    public func validate(_ arguments: JSON) throws -> [String: JSON] {
        guard let object = arguments.object else { throw ConnectorError("invalid_arguments", "Arguments must be an object.") }
        for key in required where object[key] == nil { throw ConnectorError("invalid_arguments", "Missing \(key).") }
        for (key, value) in object {
            guard let schema = properties[key] else { throw ConnectorError("invalid_arguments", "Unknown argument: \(key).") }
            let type = schema["type"]?.string
            let valid = type == "string" ? value.string != nil : type == "integer" ? (value.number.map { $0.isFinite && $0.rounded() == $0 } ?? false) : type == "array" ? (value.array?.allSatisfy { $0.string != nil } ?? false) : false
            guard valid else { throw ConnectorError("invalid_arguments", "\(key) must be a \(type ?? "valid value").") }
            if let items = value.array {
                guard items.count <= Int(schema["maxItems"]?.number ?? 20), items.allSatisfy({ ($0.string?.utf8.count ?? 0) <= Int(schema["items"]?["maxLength"]?.number ?? 80) }) else {
                    throw ConnectorError("invalid_arguments", "\(key) contains too many or overly long values.")
                }
            }
            if let choices = schema["enum"]?.array, !choices.contains(value) { throw ConnectorError("invalid_arguments", "Invalid \(key).") }
            if let count = value.string?.utf8.count, let max = schema["maxLength"]?.number, Double(count) > max {
                throw ConnectorError("invalid_arguments", "\(key) is too long.")
            }
            if let n = value.number, let min = schema["minimum"]?.number, n < min { throw ConnectorError("invalid_arguments", "\(key) is too small.") }
            if let n = value.number, let max = schema["maximum"]?.number, n > max { throw ConnectorError("invalid_arguments", "\(key) is too large.") }
        }
        return object
    }
}

public enum ToolCatalog {
    private static func string(_ description: String, max: Int = 1024) -> JSON {
        ["type": "string", "description": .string(description), "maxLength": .number(Double(max))]
    }
    private static let id = string("Stable ID returned by the corresponding list or get tool.")
    private static let revision = string("Revision returned by get. Required to avoid overwriting a newer human or agent edit.")
    private static let title = string("A non-empty title.", max: 400)
    private static let body = string("Markdown content, including headings, lists, checklists, code, and tables.", max: 262144)
    private static let start = string("ISO 8601 date-time with a timezone offset, for example 2026-10-10T09:00:00+05:30.")
    private static let status = string("Status ID from task_statuses. Built-in IDs remain backlog, todo, in_progress, done.")
    private static let page: [String: JSON] = [
        "query": string("Case-insensitive text search."),
        "limit": ["type": "integer", "minimum": 1, "maximum": 200],
        "offset": ["type": "integer", "minimum": 0, "maximum": 1000000]
    ]
    public static let tools: [ConnectorTool] = {
        func tool(_ name: String, _ description: String, _ properties: [String: JSON] = [:], _ required: [String] = [], read: Bool = true) -> ConnectorTool {
            ConnectorTool(name: name, description: description, properties: properties, required: required, readOnly: read)
        }
        let edit: [String: JSON] = ["id": id, "revision": revision]
        let taskText: [String: JSON] = ["title": title, "description": body,
            "priority": ["type": "integer", "minimum": 0, "maximum": 4, "description": "0 none, 1 urgent, 2 high, 3 normal, 4 low."],
            "project": string("Project name; empty string clears it.", max: 120),
            "assignee": string("Person responsible; a local text field, not an account or notification.", max: 120),
            "labels": ["type": "array", "items": ["type": "string", "maxLength": 80], "maxItems": 20, "description": "Replace labels; [] clears them."],
            "due_date": string("ISO 8601 date-time with timezone; empty string clears the due date."),
            "parent_id": string("Parent task UUID or ticket ID; empty string clears the parent."),
            "blocked_by": ["type": "array", "items": ["type": "string", "maxLength": 80], "maxItems": 20, "description": "Replace blocking task UUIDs or ticket IDs. [] clears. Circular dependencies are rejected."],
            "estimate": ["type": "integer", "minimum": 0, "maximum": 100, "description": "Effort points; 0 clears the estimate."]]
        let taskFields = taskText.merging(["list": id, "status": status]) { _, n in n }
        let eventFields = ["title": title, "start": start, "end": start, "calendar_id": id,
                           "location": string("Event location."), "notes": body]
        return [
            tool("foglio_status", "Check connection, enabled permissions, and the selected calendar source."),
            tool("task_lists", "List task lists. Board status is a separate field."),
            tool("task_list_create", "Create a task list, or return the existing list with that name.", ["name": title], ["name"], read: false),
            tool("task_statuses", "List ordered board statuses, stable IDs, categories, and workspace revisions."),
            tool("task_status_create", "Create a custom status within a category. Categories determine completion semantics.", ["name": string("Unique status name.", max: 80), "category": ["type": "string", "enum": ["backlog", "todo", "in_progress", "done"]]], ["name", "category"], read: false),
            tool("task_status_update", "Rename and/or reorder a status without changing task identity. Get a fresh revision from task_statuses first.", edit.merging(["name": string("Unique status name.", max: 80), "position": ["type": "integer", "minimum": 0, "maximum": 19]]) { _, n in n }, ["id", "revision"], read: false),
            tool("tasks_list", "Search and list tasks with IDs, descriptions, board statuses, and revisions.", page.merging(["list": id, "status": status, "project": string("Filter by project name."), "priority": ["type": "integer", "minimum": 0, "maximum": 4]]) { _, n in n }),
            tool("task_get", "Read a task by UUID or ticket ID (e.g. FOG-42) and get its current revision before editing.", ["id": id], ["id"]),
            tool("task_create", "Add a task. Optionally choose its list and board status.", taskFields, ["title"], read: false),
            tool("task_update", "Edit task content, properties, list, or custom status. Rejects stale revisions and tasks with an open editor.", edit.merging(taskFields) { _, n in n }, ["id", "revision"], read: false),
            tool("task_move", "Move a task between lists and/or any status returned by task_statuses. Uses Foglio's completion logging.", edit.merging(["list": id, "status": status]) { _, n in n }, ["id", "revision"], read: false),
            tool("note_folders", "List note folders and note counts."),
            tool("note_folder_create", "Create a note folder, or return the existing folder with that name.", ["name": title], ["name"], read: false),
            tool("notes_list", "Search notes by title or content. Returns summaries and IDs; use note_get for full Markdown.", page.merging(["folder": id]) { _, n in n }),
            tool("note_get", "Read a note's full Markdown and current revision, including live autosaved edits.", ["id": id], ["id"]),
            tool("note_create", "Create a Markdown note in an existing folder; defaults to Scratch.", ["title": title, "body": body, "folder": id], ["title"], read: false),
            tool("note_update", "Update a note title and/or full Markdown body. Get the current revision first.", edit.merging(["title": title, "body": body]) { _, n in n }, ["id", "revision"], read: false),
            tool("note_move", "Move a note to an existing folder without changing its contents.", edit.merging(["folder": id]) { _, n in n }, ["id", "revision", "folder"], read: false),
            tool("calendar_list", "List calendar sources and whether they can be edited. Never returns feed credentials."),
            tool("calendar_events", "Read calendar events in a date range of at most 92 days. Defaults to the visible week. Times include a timezone.", page.merging(["start": start, "end": start]) { _, n in n }),
            tool("calendar_event_get", "Read an event and its revision. For feed/file events outside the visible week, supply date from calendar_events.", ["id": id, "date": start], ["id"]),
            tool("calendar_event_create", "Create a personal event in a writable macOS calendar. Feed/file sources are read-only. Does not add attendees.", eventFields, ["title", "start", "end", "calendar_id"], read: false),
            tool("calendar_event_update", "Edit a personal event using its current revision. Invited or recurring meetings cannot be changed with this tool.", edit.merging(eventFields) { _, n in n }, ["id", "revision"], read: false),
            tool("calendar_event_move", "Reschedule a personal event and/or move it to another writable macOS calendar. Get its revision first.", edit.merging(["start": start, "end": start, "calendar_id": id]) { _, n in n }, ["id", "revision"], read: false),
            tool("meeting_note_create", "Create a note linked to a meeting. Include date for feed/file events outside the visible week.", ["event_id": id, "date": start, "folder": id, "body": body], ["event_id"], read: false),
            tool("meeting_task_create", "Add a follow-up task from a meeting. Include date for feed/file events outside the visible week.", ["event_id": id, "date": start, "title": title, "list": id], ["event_id", "title"], read: false)
        ]
    }()
    public static func find(_ name: String) -> ConnectorTool? { tools.first { $0.name == name } }
}
