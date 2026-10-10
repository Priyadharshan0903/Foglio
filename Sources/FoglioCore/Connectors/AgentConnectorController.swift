import Foundation
import FoglioConnectorKit

@MainActor
final class AgentConnectorController {
    private let state: AppState
    private let store: Store
    private let calendar: AgentCalendarProviding
    private let socketURL: URL
    private var server: LocalConnectorServer?
    private var generation = UUID()
    init(state: AppState, store: Store, calendar: AgentCalendarProviding, socketURL: URL? = nil) {
        self.state = state; self.store = store; self.calendar = calendar
        self.socketURL = socketURL ?? store.root.appendingPathComponent("agent.sock")
    }
    func applySettings() {
        if !state.agentConnectorEnabled { stop(); state.agentConnectorStatus = "Off"; return }
        if server == nil {
            let generation = self.generation
            let state = self.state
            let service = AgentService(store: store, calendar: calendar,
                enabled: { [weak self] in state.agentConnectorEnabled && self?.generation == generation },
                allowEdits: { state.agentConnectorAllowEdits }, autoLog: { state.autoLog })
            let listener = LocalConnectorServer(url: socketURL) { request, respond in
                Task { @MainActor in
                    do {
                        guard let name = request["tool"]?.string else { throw ConnectorError("invalid_request", "Missing tool name.") }
                        let result = try await service.call(name, arguments: request["arguments"] ?? [:])
                        respond(["ok": true, "result": result])
                    } catch {
                        let failure = (error as? ConnectorError) ?? ConnectorError("request_failed", "Foglio could not complete this request.")
                        respond(["ok": false, "error": failure.json])
                    }
                }
            }
            do { try listener.start(); server = listener }
            catch { state.agentConnectorStatus = "Could not connect: \(error.localizedDescription)"; return }
        }
        state.agentConnectorStatus = state.agentConnectorAllowEdits ? "Connected · Reading and editing allowed" : "Connected · Reading only"
    }
    func stop() { generation = UUID(); server?.stop(); server = nil }
}

enum AgentConnectorSetup {
    static var executable: String {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/FoglioMCP").path
        }
        return (Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL)
            .appendingPathComponent("FoglioMCP").path
    }
    private static var quotedExecutable: String {
        "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    static var codexCommand: String {
        "codex mcp add foglio -- " + quotedExecutable
    }
    /// Claude Code in the terminal and in the Claude desktop app share the
    /// user-scope MCP registry, so one command covers both.
    static var claudeCodeCommand: String {
        "claude mcp add --transport stdio --scope user foglio -- " + quotedExecutable
    }
    static var claudeConfiguration: String {
        let value: JSON = ["mcpServers": ["foglio": ["command": .string(executable), "args": []]]]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self)
    }
}
