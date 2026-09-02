import Foundation

/// Opt-in diagnostics: `FOGLIO_DEBUG=1 open -a build/Foglio.app`.
///
/// Worth keeping because this app is unusually hard to inspect from outside.
/// `screencapture` is blocked without Screen Recording permission, SwiftUI
/// publishes no accessibility children, and ad-hoc signing changes the app's
/// signature on every build — which silently revokes the terminal's automation
/// permission, so `osascript` window queries return zero windows for an app
/// that is running perfectly. A log file sidesteps all three.
enum Debug {
    private static let enabled = ProcessInfo.processInfo.environment["FOGLIO_DEBUG"] != nil
    private static let url = URL(fileURLWithPath: "/tmp/foglio-debug.log")

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(Date()) \(message())\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
