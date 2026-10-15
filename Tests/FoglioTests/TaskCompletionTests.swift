import AppKit
import SwiftUI
@testable import FoglioCore

@MainActor
func taskCompletionTests() {
    Check.suite("Task completion — native rows refresh after status moves") {
        for layout in [TaskLayout.board, .list] {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foglio-completion-\(UUID())")
            let suite = "FoglioCompletion-\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
            let store = Store(root: root); store.load()
            let state = AppState(defaults: defaults)
            state.taskLayout = layout; state.themeMode = .ember
            let done = try! store.addStatus(name: "Shipped", category: .done)
            let task = TaskItem(label: "Review the studio launch checklist", meta: "Keep **Markdown** intact.")
            store.addTask(task)

            @MainActor func mount() -> (NSHostingView<TasksView>, NSWindow) {
                let host = NSHostingView(rootView: TasksView(state: state, store: store))
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1840, height: 720),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host
                return (host, window)
            }
            @MainActor func settle(_ host: NSView) {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.7))
                host.layoutSubtreeIfNeeded()
            }
            @MainActor func pixels(_ host: NSView) -> Data? {
                // Capture the rendered surface: LazyVStack can retain hidden
                // native drag bridges from the task's previous status group.
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                return bitmap.representation(using: .png, properties: [:])
            }

            let (live, window) = mount()
            defer { window.close() }
            settle(live)
            let open = pixels(live)
            Check.expect(open != nil, "\(layout.rawValue) mounts the open task")
            store.setStatus(taskId: task.id, statusID: done.id, autoLog: false)
            settle(live)
            let completed = pixels(live)
            let (reference, referenceWindow) = mount()
            defer { referenceWindow.close() }
            settle(reference)
            let expected = pixels(reference)
            if let path = ProcessInfo.processInfo.environment["FOGLIO_TASK_PREVIEWS"] {
                try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                try? completed?.write(to: URL(fileURLWithPath: path).appendingPathComponent("regression-\(layout.rawValue)-actual.png"))
                try? expected?.write(to: URL(fileURLWithPath: path).appendingPathComponent("regression-\(layout.rawValue)-expected.png"))
            }
            Check.expect(completed != nil && expected != nil && completed == expected,
                         "\(layout.rawValue) moved task matches a freshly mounted completed task")
            Check.expect(completed != open, "\(layout.rawValue) completion visibly changes the task")
            store.setStatus(taskId: task.id, statusID: "todo", autoLog: false)
            settle(live)
            Check.expect(pixels(live) == open, "\(layout.rawValue) reopening restores the original task appearance")
        }
    }
}
