import AppKit
import SwiftUI
@testable import FoglioCore

/// Optional native snapshots of the task redesign with isolated fictional data.
@MainActor
func renderTaskPreviewsIfRequested() {
    guard let path = ProcessInfo.processInfo.environment["FOGLIO_TASK_PREVIEWS"] else { return }
    Typo.registerBundledFonts()
    let output = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foglio-task-preview-\(UUID())")
    let suite = "FoglioTaskPreview-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
    let store = Store(root: root); store.load()
    let state = AppState(defaults: defaults); state.section = .tasks; state.themeMode = .ember
    let calendar = CalendarSource(defaults: defaults, cacheRoot: root.appendingPathComponent("calendar"))
    let list = store.addLane(named: "Studio")!
    let review = try! store.addStatus(name: "In review", category: .inProgress)
    let parent = TaskItem(label: "Launch the studio collection", lane: list, meta: "Bring the first collection together with a clear story and a thoughtful release.", workflow: .inProgress, priority: .high, project: "Studio launch", assignee: "Me", labels: ["Release", "Design"], dueDate: Date(timeIntervalSince1970: 1791849600), estimate: 5)
    store.addTask(parent)
    for (title, status, priority) in [
        ("Gather references for the next collection", TaskWorkflow.backlog, TaskPriority.low),
        ("Design the welcome page", .todo, .high),
        ("Write the release announcement", .todo, .normal),
        ("Review the first sketches", .inProgress, .urgent),
        ("Refine the launch checklist", .done, .normal)
    ] {
        let task = TaskItem(label: title, lane: list, meta: "Keep the next step clear. Make room for the details that matter.", priority: priority, project: "Studio launch", labels: ["Release"], estimate: 3, parentID: parent.id)
        store.addTask(task); store.setWorkflow(taskId: task.id, status: status, autoLog: false)
        if title.hasPrefix("Review") { store.setStatus(taskId: task.id, statusID: review.id, autoLog: false) }
    }
    var updated = store.tasks.first { $0.id == parent.id }!
    updated.blockedBy = [store.tasks.first { $0.label.hasPrefix("Review") }!.id]; store.update(updated)
    func render<Content: View>(_ name: String, width: CGFloat, height: CGFloat, content: Content) {
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.3)); host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        window.close()
    }
    for mode in [ThemeMode.ember, .harbor] {
        state.themeMode = mode
        render("board-" + mode.rawValue, width: 1840, height: 940, content: MainWindowView(state: state, store: store, calendar: calendar))
        render("editor-" + mode.rawValue, width: 1080, height: 800, content: TaskDetailEditor(task: updated, isNew: false, store: store, theme: mode.theme, autoLog: false, onClose: {}, onDelete: {}))
    }
    render("statuses", width: 600, height: 620, content: TaskStatusManager(store: store, theme: .ember))
    let previewToday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 11))!
    let previewDate = Calendar.current.date(byAdding: .day, value: 3, to: previewToday)!
    for mode in ThemeMode.allCases {
        render("date-picker-" + mode.rawValue, width: 292, height: 378,
               content: ThemedDateCalendar(selection: .constant(previewDate), theme: mode.theme,
                                           today: previewToday, onClose: {}))
        render("drag-feedback-" + mode.rawValue, width: 344, height: 540,
               content: TaskDragFeedbackPreview(theme: mode.theme))
    }
    print("Task previews saved to \(path)")
}

/// Actual drag decorations with simulated hover feedback and fictional cards.
/// This checks theme/placement rendering, not a live native drag session.
private struct TaskDragFeedbackPreview: View {
    let theme: Theme
    var body: some View {
        VStack(spacing: 12) {
            Text("Same-lane drag feedback").font(Typo.sans(12)).foregroundStyle(theme.muted)
            VStack(alignment: .leading, spacing: 8) {
                Label("To do", systemImage: "circle").font(Typo.sans(13, .semibold)).foregroundStyle(theme.text)
                    .frame(height: 32)
                sampleCard("FOG-12", "Prepare the welcome page")
                TaskDropPlaceholder(height: 120, theme: theme)
                sampleCard("FOG-15", "Review the launch checklist")
                Spacer(minLength: 0)
            }
            .padding(12).frame(width: 320, height: 480, alignment: .topLeading)
            .modifier(TaskColumnDropDecoration(active: true, insertionY: 177, theme: theme))
        }.frame(width: 344, height: 540).background(theme.bg)
    }
    private func sampleCard(_ ticket: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ticket).font(Typo.mono(10.5)).foregroundStyle(theme.muted)
            Text(title).font(Typo.sans(13, .medium)).foregroundStyle(theme.text)
            Label("Studio launch", systemImage: "square.stack").font(Typo.sans(11)).foregroundStyle(theme.muted)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
            .background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line, lineWidth: 1))
    }
}
