import Foundation
import FoglioConnectorKit

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--help"] {
    FileHandle.standardError.write(Data("FoglioMCP: local MCP stdio server. Open Foglio and enable Settings → Agent connections. Optional: --socket /absolute/path/agent.sock\n".utf8))
    exit(0)
}
var socket = ConnectorSocket.defaultURL
if !args.isEmpty {
    guard args.count == 2, args[0] == "--socket", args[1].hasPrefix("/") else {
        FileHandle.standardError.write(Data("Usage: FoglioMCP [--socket /absolute/path/agent.sock]\n".utf8)); exit(2)
    }
    socket = URL(fileURLWithPath: args[1])
}
let server = FoglioMCPServer { name, arguments in
    let response = try ConnectorSocket.request(["tool": .string(name), "arguments": arguments], at: socket)
    guard response["ok"] == true, let result = response["result"] else {
        throw ConnectorError(response["error"]?["error"]?.string ?? "app_error",
                             response["error"]?["message"]?.string ?? "Foglio could not complete the request.")
    }
    return result
}
while let line = readLine() {
    if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
    let response: JSON?
    do {
        guard line.utf8.count < ConnectorSocket.maximumMessageBytes else { throw ConnectorError("message_too_large", "Request exceeds 4 MiB.") }
        response = server.handle(try JSON.decode(Data(line.utf8)))
    } catch {
        response = ["jsonrpc": "2.0", "id": .null, "error": ["code": -32700, "message": "Invalid JSON message."]]
    }
    if let response, let data = try? response.data() {
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    }
}
