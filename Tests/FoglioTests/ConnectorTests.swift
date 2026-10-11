import Foundation
import Darwin
import FoglioConnectorKit
@testable import FoglioCore

func connectorProtocolTests() {
    Check.suite("MCP — lifecycle, schemas, and errors") {
        var called = 0
        let mcp = FoglioMCPServer { _, _ in called += 1; return ["connected": true] }
        func request(_ method: String, _ params: JSON = [:]) -> JSON {
            mcp.handle(["jsonrpc": "2.0", "id": 1, "method": .string(method), "params": params])!
        }
        Check.equal(request("tools/list")["error"]?["code"], -32002, "tools require initialization")
        let initialized = request("initialize", ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]])
        Check.equal(initialized["result"]?["protocolVersion"], "2025-11-25", "negotiates the MCP version")
        Check.expect(initialized["result"]?["instructions"]?.string?.contains("revision") == true, "server instructions explain edit conflicts")
        Check.expect(initialized["result"]?["instructions"]?.string?.contains("order_revision") == true, "agents discover the ordering conflict token at initialization")
        Check.expect(mcp.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil, "notifications produce no stdout response")
        Check.equal(request("tools/list")["result"]?["tools"]?.array?.count, 26, "all connector tools are discoverable")
        Check.equal(request("tools/call", ["name": "foglio_status"])["result"]?["structuredContent"]?["connected"], true, "returns structured tool data")
        let missingRevision = request("tools/call", ["name": "note_update", "arguments": ["id": "x", "body": "text"]])
        Check.equal(missingRevision["result"]?["isError"], true, "missing edit revision is a tool error")
        Check.equal(called, 1, "invalid arguments never reach the app")
        Check.equal(request("tools/call", ["name": "not_a_tool"])["error"]?["code"], -32602, "unknown tool is a protocol error")
        Check.equal(request("unknown")["error"]?["code"], -32601, "unknown method returns method-not-found")
        Check.equal(request("tools/call", ["name": "tasks_list", "arguments": ["limit": 0]])["result"]?["isError"], true, "pagination limits are validated")
        Check.equal(request("tools/call", ["name": "task_create", "arguments": ["title": "A", "status": 1]])["result"]?["isError"], true, "invalid workflow is rejected")
        Check.equal(request("tools/call", ["name": "note_create", "arguments": ["title": "A", "path": "/tmp/file"]])["result"]?["isError"], true, "tools cannot request arbitrary file paths")
        Check.equal(Set(ToolCatalog.tools.map(\.name)).count, ToolCatalog.tools.count, "tool names are unique")
        let offline = FoglioMCPServer { _, _ in throw ConnectorError("app_unavailable", "Open Foglio.") }
        _ = offline.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2024-11-05", "capabilities": [:], "clientInfo": ["name": "legacy", "version": "1"]]])
        _ = offline.handle(["jsonrpc": "2.0", "method": "notifications/initialized"])
        Check.equal(offline.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "foglio_status"]])?["result"]?["structuredContent"]?["error"], "app_unavailable", "offline errors remain valid MCP tool results")
    }
    Check.suite("Connector socket — local transport and permissions") {
        let root = URL(fileURLWithPath: "/tmp/foglio-ipc-\(UUID().uuidString.prefix(8))")
        let socket = root.appendingPathComponent("agent.sock")
        let server = LocalConnectorServer(url: socket) { request, reply in reply(["ok": true, "echo": request]) }
        defer { server.stop(); try? FileManager.default.removeItem(at: root) }
        do {
            try server.start()
            let response = try ConnectorSocket.request(["message": "Unicode ✓\nMarkdown"], at: socket)
            Check.equal(response["echo"]?["message"], "Unicode ✓\nMarkdown", "IPC preserves Unicode and embedded newlines")
            let permissions = try FileManager.default.attributesOfItem(atPath: socket.path)[.posixPermissions] as? Int
            Check.equal(permissions, 0o600, "socket is private to the user")
            Check.equal(try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int, 0o700, "directory is private to the user")
            let duplicate = LocalConnectorServer(url: socket) { _, reply in reply([:]) }
            do { try duplicate.start(); Check.expect(false, "duplicate listener must fail") }
            catch { Check.equal((error as? ConnectorError)?.code, "already_running", "a second listener cannot displace the first") }
            server.stop()
            Check.expect(!FileManager.default.fileExists(atPath: socket.path), "stopping removes the socket")
            try Data("keep".utf8).write(to: socket)
            let replacement = LocalConnectorServer(url: socket) { _, reply in reply([:]) }
            do { try replacement.start(); Check.expect(false, "regular file must not be replaced") }
            catch { Check.equal((error as? ConnectorError)?.code, "unsafe_socket", "does not replace a regular file") }
            Check.equal(try String(contentsOf: socket, encoding: .utf8), "keep", "file contents are untouched")
        } catch { Check.expect(false, "socket check failed: \(error.localizedDescription)") }
    }

    Check.suite("Connector — copied setup") {
        let quoted = "'" + AgentConnectorSetup.executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        Check.equal(AgentConnectorSetup.codexCommand, "codex mcp add foglio -- " + quoted, "Codex command points at the helper")
        Check.equal(AgentConnectorSetup.claudeCodeCommand, "claude mcp add --transport stdio --scope user foglio -- " + quoted,
                    "Claude Code command registers the helper for every project")
        Check.expect(AgentConnectorSetup.claudeConfiguration.contains(AgentConnectorSetup.executable), "Claude Desktop config points at the helper")
    }
}

@MainActor
private final class FixtureAgentCalendar: AgentCalendarProviding {
    var connectorInfo: JSON { ["backend": "fixture", "writable": true] }
    var connectorRange = DateInterval(start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 10000))
    var writable = true
    var event = AgentEvent(id: "meeting-1", title: "Studio review", start: Date(timeIntervalSince1970: 2000), end: Date(timeIntervalSince1970: 4000),
                           location: "Studio", notes: "Review sketches", calendarID: "studio", calendarName: "Studio", organizer: "", attendees: [], writable: true, revision: "event-revision")
    var pause: CheckedContinuation<Void, Never>?
    var shouldPause = false
    func connectorCalendars() throws -> [JSON] { [["id": "studio", "name": "Studio", "writable": .bool(writable)]] }
    func connectorEvents(in range: DateInterval) async throws -> [AgentEvent] { [event] }
    func connectorEvent(id: String, date: Date?) async throws -> AgentEvent {
        if shouldPause { await withCheckedContinuation { pause = $0 } }
        guard id == event.id else { throw ConnectorError("not_found", "No event.") }; return event
    }
    func connectorCreateEvent(fields: [String: JSON]) throws -> AgentEvent {
        guard writable else { throw ConnectorError("calendar_read_only", "Source is read-only.") }; return event
    }
    func connectorUpdateEvent(id: String, revision: String, fields: [String: JSON]) throws -> AgentEvent {
        guard writable else { throw ConnectorError("calendar_read_only", "Source is read-only.") }
        guard revision == event.revision else { throw ConnectorError("conflict", "Event changed.") }; return event
    }
}

@MainActor
func connectorIntegrationTests() async {
    let root = URL(fileURLWithPath: "/tmp/foglio-agents-\(UUID().uuidString.prefix(8))")
    let store = Store(root: root); store.load()
    defer { try? FileManager.default.removeItem(at: root) }
    let calendar = FixtureAgentCalendar()
    var enabled = true, edits = false
    let service = AgentService(store: store, calendar: calendar, enabled: { enabled }, allowEdits: { edits })
    func call(_ name: String, _ args: JSON = [:]) async throws -> JSON { try await service.call(name, arguments: args) }
    func fails(_ name: String, _ args: JSON = [:], code: String) async {
        do { _ = try await call(name, args); Check.expect(false, "\(name) must reject \(code)") }
        catch { Check.equal((error as? ConnectorError)?.code, code, "\(name) rejects \(code)") }
    }
    Check.suite("Agents — permissions and validation") {}
    await fails("task_create", ["title": "No edit permission"], code: "read_only")
    enabled = false; await fails("notes_list", code: "disabled"); enabled = true
    edits = true
    await fails("note_create", ["title": "\n"], code: "invalid_arguments")
    await fails("note_create", ["title": "Title\nid: injected"], code: "invalid_arguments")
    await fails("task_create", ["title": "Unknown list", "list": "missing"], code: "not_found")
    await fails("task_get", ["id": "invalid"], code: "not_found")
    do {
        Check.suite("Agents — task create, edit, move, conflicts, and persistence") {}
        let list = try await call("task_list_create", ["name": "Studio"])
        Check.equal(list["id"], "studio", "creates a task list")
        let created = try await call("task_create", ["title": "Ship agent tools", "description": "- [ ] Document setup", "list": "studio", "status": "backlog"])
        let id = created["id"]!, originalRevision = created["revision"]!
        let updated = try await call("task_update", ["id": id, "revision": originalRevision, "description": "**Ready**\n\n- [x] Document setup"])
        Check.equal(updated["title"], "Ship agent tools", "editing details keeps the title")
        await fails("task_move", ["id": id, "revision": originalRevision, "status": "done"], code: "conflict")
        store.editingTaskIds.insert(UUID(uuidString: id.string!)!)
        await fails("task_update", ["id": id, "revision": updated["revision"]!, "title": "Overwrite draft"], code: "resource_busy")
        store.editingTaskIds.removeAll()
        let beforeLog = store.log.count
        let done = try await call("task_move", ["id": id, "revision": updated["revision"]!, "status": "done"])
        Check.equal(done["status"], "done", "task moves to Done")
        Check.equal(store.log.count, beforeLog + 1, "completion uses the app's activity log")
        Check.expect(done["completed_at"]?.string != nil, "completion gets a timestamp")
        let reopened = try await call("task_move", ["id": id, "revision": done["revision"]!, "status": "in_progress"])
        Check.equal(reopened["completed_at"], .null, "reopening clears completion metadata")
        Check.equal(try await call("tasks_list", ["status": "in_progress", "list": "studio"])["total"], 1, "task filters match board status and list")
        let reloaded = Store(root: root); reloaded.load()
        Check.expect(reloaded.tasks.contains { $0.id.uuidString == id.string && $0.workflowStatus == .inProgress }, "task changes survive relaunch")

        Check.suite("Agents — custom workflow, ticket IDs, and structured properties") {}
        let custom = try await call("task_status_create", ["name": "Waiting", "category": "in_progress"])
        let renamedStatus = try await call("task_status_update", ["id": custom["id"]!, "revision": custom["revision"]!, "name": "Review", "position": 0])
        Check.equal(renamedStatus["id"], custom["id"], "renaming preserves the status ID")
        await fails("task_status_update", ["id": custom["id"]!, "revision": custom["revision"]!, "name": "Stale rename"], code: "conflict")
        let ticket = try await call("task_create", ["title": "Review release", "status": custom["id"]!, "priority": 2, "project": "Foglio", "labels": ["Release", "release", "UX"], "assignee": "Me", "estimate": 5, "due_date": "2026-10-12T09:00:00+05:30"])
        Check.expect(ticket["ticket_id"]?.string?.hasPrefix("FOG-") == true, "tasks expose readable ticket IDs")
        Check.equal(try await call("task_get", ["id": ticket["ticket_id"]!])["id"], ticket["id"], "ticket ID resolves the same task as its UUID")
        Check.equal(ticket["status_name"], "Review", "custom names are exposed to agents")
        Check.equal(ticket["labels"]?.array?.count, 2, "labels are deduplicated case-insensitively")
        Check.equal(try await call("tasks_list", ["status": custom["id"]!, "priority": 2, "project": "Foglio"])["total"], 1, "custom status and properties can filter tasks")
        let cleared = try await call("task_update", ["id": ticket["id"]!, "revision": ticket["revision"]!, "project": "", "labels": [], "due_date": "", "estimate": 0])
        Check.equal(cleared["ticket_id"], ticket["ticket_id"], "editing preserves ticket IDs")
        Check.equal(cleared["due_date"], .null, "due date can be cleared")
        Check.equal(cleared["labels"]?.array?.count, 0, "labels can be cleared")
        await fails("task_update", ["id": ticket["id"]!, "revision": cleared["revision"]!, "due_date": "tomorrow"], code: "invalid_date")
        await fails("task_create", ["title": "Bad", "status": "unknown"], code: "invalid_status")
        await fails("task_create", ["title": "Bad", "priority": 9], code: "invalid_arguments")
        await fails("task_create", ["title": "Bad", "labels": [" "]], code: "invalid_arguments")
        edits = false
        await fails("task_status_create", ["name": "Forbidden", "category": "todo"], code: "read_only")
        edits = true

        Check.suite("Agents — parent tasks and blockers") {}
        let parentTask = try await call("task_create", ["title": "Parent release"])
        let childTask = try await call("task_create", ["title": "Child review", "parent_id": parentTask["ticket_id"]!])
        let dependent = try await call("task_create", ["title": "Publish", "blocked_by": .array([childTask["ticket_id"]!])])
        Check.equal(dependent["is_blocked"], true, "an incomplete blocker is reported")
        let parentRead = try await call("task_get", ["id": parentTask["id"]!])
        Check.equal(parentRead["subtask_ids"]?.array?.first, childTask["id"], "parent reads expose subtasks")
        await fails("task_update", ["id": parentTask["id"]!, "revision": parentRead["revision"]!, "parent_id": childTask["id"]!], code: "invalid_relation")
        await fails("task_update", ["id": childTask["id"]!, "revision": childTask["revision"]!, "blocked_by": .array([dependent["id"]!])], code: "invalid_relation")
        _ = try await call("task_move", ["id": childTask["id"]!, "revision": childTask["revision"]!, "status": "done"])
        Check.equal(try await call("task_get", ["id": dependent["id"]!])["is_blocked"], false, "completing a dependency clears the blocked indicator")

        Check.suite("Agents — manual ordering, validation, and stale order protection") {}
        let orderA = try await call("task_create", ["title": "Order A"])
        let orderB = try await call("task_create", ["title": "Order B"])
        let orderC = try await call("task_create", ["title": "Order C"])
        let orderRead = try await call("task_get", ["id": orderA["id"]!])
        let orderArgs: JSON = ["id": orderA["ticket_id"]!, "revision": orderRead["revision"]!, "before_id": orderC["ticket_id"]!, "order_revision": orderRead["order_revision"]!]
        edits = false; await fails("task_move", orderArgs, code: "read_only"); edits = true
        await fails("task_move", ["id": orderA["id"]!, "revision": orderRead["revision"]!, "before_id": orderC["id"]!], code: "invalid_arguments")
        await fails("task_move", ["id": orderA["id"]!, "revision": orderRead["revision"]!, "before_id": orderC["id"]!, "after_id": orderB["id"]!, "order_revision": orderRead["order_revision"]!], code: "invalid_arguments")
        await fails("task_move", ["id": orderA["id"]!, "revision": orderRead["revision"]!, "before_id": orderA["id"]!, "order_revision": orderRead["order_revision"]!], code: "invalid_arguments")
        await fails("task_move", ["id": orderA["id"]!, "revision": orderRead["revision"]!, "before_id": "FOG-999999", "order_revision": orderRead["order_revision"]!], code: "not_found")
        await fails("task_move", ["id": orderA["id"]!, "revision": orderRead["revision"]!, "before_id": ticket["id"]!, "status": "done", "order_revision": orderRead["order_revision"]!], code: "invalid_arguments")
        Check.equal(try await call("task_get", ["id": orderA["id"]!])["status"], "todo", "invalid placement does not partially complete a task")
        let orderUUID = UUID(uuidString: orderA["id"]!.string!)!
        store.editingTaskIds.insert(orderUUID)
        await fails("task_move", orderArgs, code: "resource_busy")
        store.editingTaskIds.remove(orderUUID)
        let placed = try await call("task_move", orderArgs)
        Check.equal(placed["revision"], orderRead["revision"], "reorder preserves the content revision")
        Check.expect(placed["order_revision"] != orderRead["order_revision"], "reorder updates the order revision")
        await fails("task_move", orderArgs, code: "conflict")
        let listed = try await call("tasks_list", ["query": "Order ", "limit": 1])
        Check.equal(listed["tasks"]?.array?.first?["id"], orderA["id"], "MCP pagination follows the visible saved order")
        Check.equal(listed["order_revision"], placed["order_revision"], "filtered pagination returns the global order revision")
        let placedAfter = try await call("task_move", ["id": orderA["id"]!, "revision": placed["revision"]!, "after_id": orderB["id"]!, "order_revision": placed["order_revision"]!])
        let reorderedList = try await call("tasks_list", ["query": "Order "])
        Check.equal(reorderedList["tasks"]?.array?.map { $0["id"]! }, [orderC["id"]!, orderB["id"]!, orderA["id"]!], "after_id moves down without losing cards")
        let freshOrder = try await call("task_get", ["id": orderA["id"]!])
        store.setStatus(taskId: UUID(uuidString: orderB["id"]!.string!)!, statusID: "backlog", autoLog: false)
        await fails("task_move", ["id": orderA["id"]!, "revision": freshOrder["revision"]!, "before_id": orderC["id"]!, "order_revision": freshOrder["order_revision"]!], code: "conflict")
        let crossRead = try await call("task_get", ["id": orderA["id"]!])
        let crossPlaced = try await call("task_move", ["id": orderA["id"]!, "revision": crossRead["revision"]!, "status": "backlog", "before_id": orderB["id"]!, "order_revision": crossRead["order_revision"]!])
        Check.equal(crossPlaced["status"], "backlog", "MCP combines status change and placement")
        let orderedReloaded = Store(root: root); orderedReloaded.load()
        Check.equal(orderedReloaded.manuallyOrderedTasks.map(\.id), store.manuallyOrderedTasks.map(\.id), "agent order survives reopening")
        Check.expect(placedAfter["order_revision"]?.string != nil, "write responses include the next ordering token")

        Check.suite("Agents — Markdown notes, autosaves, folders, and revisions") {}
        _ = try await call("note_folder_create", ["name": "Research"])
        let markdown = "# Plan\n\n1. First\n2. Second\n\n- [ ] Capture\n\n| A | B |\n| --- | --- |\n| 1 | 2 |"
        let note = try await call("note_create", ["title": "Connector design", "body": .string(markdown)])
        let noteID = note["id"]!
        let moved = try await call("note_move", ["id": noteID, "revision": note["revision"]!, "folder": "research"])
        Check.equal(moved["body"], .string(markdown), "moving preserves full Markdown")
        Check.equal(moved["folder"], "research", "note moves to the folder")
        let uuid = UUID(uuidString: noteID.string!)!
        store.updateNoteBody(id: uuid, body: markdown + "\n\nHuman edit")
        await fails("note_update", ["id": noteID, "revision": moved["revision"]!, "body": "Outdated replacement"], code: "conflict")
        let latest = try await call("note_get", ["id": noteID])
        Check.expect(latest["body"]?.string?.contains("Human edit") == true, "get sees in-memory typing before the debounce fires")
        let renamed = try await call("note_update", ["id": noteID, "revision": latest["revision"]!, "title": "Final design"])
        Check.expect(renamed["body"]?.string?.contains("Human edit") == true, "title updates preserve human text")
        Check.equal(try await call("notes_list", ["query": "Human edit", "folder": "research", "limit": 1])["total"], 1, "notes search full content in the requested folder")
        let noteReload = Store(root: root); noteReload.load()
        Check.equal(noteReload.note(id: uuid)?.title, "Final design", "renamed note survives relaunch")
        Check.expect(noteReload.note(id: uuid)?.body.contains("Human edit") == true, "live edits flush with agent updates")
        Check.equal(try await call("notes_list", ["limit": 1, "offset": 100])["notes"]?.array?.count, 0, "offset beyond the library returns an empty page")

        Check.suite("Agents — calendar and meeting workflow") {}
        Check.equal(try await call("calendar_events")["events"]?.array?.first?["title"], "Studio review", "reads event details")
        await fails("calendar_events", ["start": "2026-01-01T00:00:00Z", "end": "2027-01-01T00:00:00Z"], code: "invalid_range")
        await fails("calendar_event_create", ["title": "Backwards", "start": "2026-10-10T10:00:00+05:30", "end": "2026-10-10T09:00:00+05:30", "calendar_id": "studio"], code: "invalid_range")
        await fails("calendar_event_move", ["id": "meeting-1", "revision": "stale", "start": "2026-10-10T09:00:00Z"], code: "conflict")
        calendar.writable = false
        await fails("calendar_event_create", ["title": "Read-only feed", "start": "2026-10-10T09:00:00Z", "end": "2026-10-10T10:00:00Z", "calendar_id": "studio"], code: "calendar_read_only")
        let meetingNote = try await call("meeting_note_create", ["event_id": "meeting-1", "body": "Decisions"])
        Check.expect(meetingNote["body"]?.string?.contains("Decisions") == true, "can capture meeting notes from a read-only source")
        Check.expect(meetingNote["linked_to"]?.string?.hasPrefix("Meeting:") == true, "meeting note records its source")
        Check.equal(meetingNote["linked_to"], "Meeting: Studio review", "meeting notes display a readable link instead of a technical ID")
        let linkedReload = Store(root: root); linkedReload.load()
        Check.equal(linkedReload.note(id: UUID(uuidString: meetingNote["id"]!.string!)!)?.sourceEventID, "meeting-1", "meeting source metadata survives a Markdown round trip")
        Check.expect(try await call("meeting_task_create", ["event_id": "meeting-1", "title": "Share sketches"])["description"]?.string?.contains("Studio review") == true, "follow-up tasks retain meeting context")

        Check.suite("Agents — revocation while a request awaits its calendar") {}
        calendar.shouldPause = true
        let count = store.notes.count
        let pending = Task { try await call("meeting_note_create", ["event_id": "meeting-1"]) }
        while calendar.pause == nil { await Task.yield() }
        edits = false; calendar.pause?.resume(); calendar.pause = nil
        do { _ = try await pending.value; Check.expect(false, "revoked edits must not save") }
        catch { Check.equal((error as? ConnectorError)?.code, "read_only", "late permission revocation blocks the write") }
        Check.equal(store.notes.count, count, "revocation leaves the library unchanged")
        calendar.shouldPause = false; edits = true

        await connectorProcessTest(store: store, calendar: calendar, root: root)
    } catch { Check.expect(false, "agent integration failed: \(error.localizedDescription)") }
    await connectorFileCalendarTest(root: root)
    Check.suite("Agents — storage failure is reported") {}
    do {
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blocked)
        let brokenStore = Store(root: blocked); brokenStore.load()
        let broken = AgentService(store: brokenStore, calendar: calendar, enabled: { true }, allowEdits: { true })
        do { _ = try await broken.call("task_create", arguments: ["title": "Must report save failure"]); Check.expect(false, "disk failure must surface") }
        catch { Check.equal((error as? ConnectorError)?.code, "save_failed", "does not claim success when persistence fails") }
    } catch { Check.expect(false, "could not prepare storage fixture") }
}

@MainActor
private func connectorFileCalendarTest(root: URL) async {
    Check.suite("Agent calendar — actual ICS source, private configuration, and UI week") {}
    let domain = "foglio-connector-calendar-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defaults.set("file", forKey: "calendarBackend")
    let file = root.appendingPathComponent("calendar-test.ics")
    defaults.set(file.path, forKey: "calendarImportPath")
    defer { defaults.removePersistentDomain(forName: domain) }
    do {
        try "BEGIN:VCALENDAR\nX-WR-CALNAME:Studio\nBEGIN:VEVENT\nUID:fixture\nSUMMARY:Design review\nDTSTART:20261010T090000Z\nDTEND:20261010T100000Z\nEND:VEVENT\nEND:VCALENDAR".write(to: file, atomically: true, encoding: .utf8)
        let calendar = CalendarSource(defaults: defaults, cacheRoot: root)
        let visibleRange = calendar.range
        let range = DateInterval(start: try AgentRevision.parse("2026-10-10T00:00:00Z"), end: try AgentRevision.parse("2026-10-11T00:00:00Z"))
        let events = try await calendar.connectorEvents(in: range)
        Check.equal(events.first?.title, "Design review", "connector reads the actual ICS parser and configured file")
        Check.equal(calendar.range, visibleRange, "agent queries do not change the user's visible week")
        Check.equal(events.first?.writable, false, "imported calendar events are read-only")
        Check.expect(try calendar.connectorInfo.text().contains(file.path) == false, "connection info does not leak import paths")
        do { _ = try calendar.connectorCreateEvent(fields: [:]); Check.expect(false, "file source must reject edits") }
        catch { Check.equal((error as? ConnectorError)?.code, "calendar_read_only", "real file backend rejects calendar writes") }
    } catch { Check.expect(false, "calendar connector fixture failed: \(error.localizedDescription)") }
}

@MainActor
private func connectorProcessTest(store: Store, calendar: AgentCalendarProviding, root: URL) async {
    Check.suite("Agents — real stdio executable through the running app service") {}
    let domain = "foglio-agent-state-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let state = AppState(defaults: defaults)
    Check.expect(!state.agentConnectorEnabled && !state.agentConnectorAllowEdits, "new installs start with agent access off")
    state.agentConnectorEnabled = true; state.agentConnectorAllowEdits = true
    let socket = root.appendingPathComponent("agent.sock")
    let controller = AgentConnectorController(state: state, store: store, calendar: calendar, socketURL: socket)
    controller.applySettings()
    defer { controller.stop() }
    let binary = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("FoglioMCP")
    let lines: [JSON] = [
        ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-11-25", "clientInfo": ["name": "fixture", "version": "1"], "capabilities": [:]]],
        ["jsonrpc": "2.0", "method": "notifications/initialized"],
        ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
        ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "task_create", "arguments": ["title": "Created over MCP"]]],
        ["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "tasks_list", "arguments": ["query": "Created over MCP"]]]
    ]
    do {
        let input = try lines.map { try $0.text() }.joined(separator: "\n") + "\n"
        let (data, code) = try await Task.detached { () -> (Data, Int32) in
            let process = Process(); process.executableURL = binary; process.arguments = ["--socket", socket.path]
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
            try process.run(); stdin.fileHandleForWriting.write(Data(input.utf8)); try stdin.fileHandleForWriting.close()
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit(); return (output, process.terminationStatus)
        }.value
        let responses = try String(decoding: data, as: UTF8.self).split(separator: "\n").map { try JSON.decode(Data($0.utf8)) }
        Check.equal(code, 0, "stdio process exits cleanly")
        Check.equal(responses.count, 4, "stdout contains only JSON-RPC responses, with no build or app logs")
        Check.equal(responses.last?["result"]?["structuredContent"]?["total"], 1, "stdio calls read the task just created via app IPC")
        Check.expect(store.tasks.contains { $0.label == "Created over MCP" }, "agent edits reach the app's actual live Store")
        let current = store.tasks.first { $0.label == "Created over MCP" }!
        let editA: JSON = ["tool": "task_update", "arguments": ["id": .string(current.id.uuidString), "revision": .string(AgentRevision.of(current)), "title": "Agent A"]]
        let editB: JSON = ["tool": "task_update", "arguments": ["id": .string(current.id.uuidString), "revision": .string(AgentRevision.of(current)), "title": "Agent B"]]
        async let first = Task.detached { try ConnectorSocket.request(editA, at: socket) }.value
        async let second = Task.detached { try ConnectorSocket.request(editB, at: socket) }.value
        let simultaneous = try await [first, second]
        Check.equal(simultaneous.filter { $0["ok"] == true }.count, 1, "two concurrent agents cannot overwrite each other's task edit")
        Check.equal(simultaneous.filter { $0["error"]?["error"] == "conflict" }.count, 1, "the losing edit receives a revision conflict")
        if let fixture = calendar as? FixtureAgentCalendar {
            fixture.shouldPause = true
            let count = store.notes.count
            let interrupted = Task.detached { try ConnectorSocket.request(["tool": "meeting_note_create", "arguments": ["event_id": "meeting-1"]], at: socket) }
            while fixture.pause == nil { await Task.yield() }
            state.agentConnectorEnabled = false; controller.applySettings()
            state.agentConnectorEnabled = true; controller.applySettings()
            fixture.pause?.resume(); fixture.pause = nil; fixture.shouldPause = false
            _ = try? await interrupted.value
            await Task.yield()
            Check.equal(store.notes.count, count, "reenabling access cannot revive a request from a revoked connection")
            Check.expect(FileManager.default.fileExists(atPath: socket.path), "the new connection remains available")
        }
        state.agentConnectorEnabled = false; controller.applySettings()
        Check.expect(!FileManager.default.fileExists(atPath: socket.path), "settings disable removes the live endpoint")
    } catch { Check.expect(false, "stdio integration failed: \(error.localizedDescription)") }
}
