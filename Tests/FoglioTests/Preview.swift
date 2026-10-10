import AppKit
import SwiftUI
@testable import FoglioCore

/// Opt-in visual QA against an isolated library; never launches the real app
/// or touches its notes, tasks, calendar, or preferences.
@MainActor
func renderPreviewsIfRequested() {
    guard let output = ProcessInfo.processInfo.environment["FOGLIO_PREVIEW_DIR"] else { return }
    _ = NSApplication.shared
    Typo.registerBundledFonts()
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foglio-preview-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let defaults = UserDefaults(suiteName: "FoglioPreview-\(UUID())")!
    let state = AppState(defaults: defaults)
    let store = Store(root: root)
    store.load()
    let sample = Note(title: "A quieter place to plan", body: """
    Keep the **important things** close, and leave room to think.

    ## A few things for today
    - Review the new designs
    - Take a proper lunch break
    - Write down the next small step

    ## Before I call it a day
    - [x] Clear my desk
    - [ ] Send the project update

    One thing at a time is enough.

    > Small improvements make a calmer workspace.

    \u{0060}\u{0060}\u{0060}swift
    let nextStep = "Keep it simple"
    \u{0060}\u{0060}\u{0060}
    """, folder: .scratch)
    store.upsert(sample)
    state.activeNoteId = sample.id
    store.addTask(TaskItem(label: "Review the new designs", lane: store.defaultLane, meta: "Start with the notes screen"))
    store.addTask(TaskItem(label: "Send the project update", lane: store.defaultLane))
    let calendar = CalendarSource()
    let directory = URL(fileURLWithPath: output)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    func render<Content: View>(_ name: String, width: Double = 1200, height: Double = 760, content: Content) {
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent(name + ".png"))
            }
        }
        window.close()
    }

    for (name, mode, width) in [
        ("notes-light", ThemeMode.light, 1200.0),
        ("notes-dark", ThemeMode.dark, 1200.0),
        ("notes-harbor", ThemeMode.harbor, 1200.0),
        ("notes-compact", ThemeMode.light, 900.0),
    ] {
        state.section = .notes
        state.themeMode = mode
        render(name, width: width, content: MainWindowView(state: state, store: store, calendar: calendar))
    }
    for mode in ThemeMode.allCases {
        render("checklist-" + mode.rawValue, width: 560, height: 420,
               content: ChecklistPreview(theme: mode.theme))
    }
    store.addTask(TaskItem(label: "Clear my desk", lane: store.defaultLane, done: true, completedAt: Clock.now()))
    if let task = store.tasks.first {
        store.setWorkflow(taskId: task.id, status: .inProgress, autoLog: false)
    }
    store.addTask(TaskItem(label: "Explore a quieter dashboard", lane: store.defaultLane, workflow: .backlog))
    store.addTask(TaskItem(label: "Polish the checklist spacing", lane: store.defaultLane, workflow: .inProgress))
    store.addTask(TaskItem(label: "Write the release notes", lane: store.defaultLane))
    store.addTask(TaskItem(label: "Review the calendar", lane: store.defaultLane, done: true))
    let work = store.addLane(named: "Work")!
    for task in store.tasks { store.move(taskId: task.id, to: work) }
    for mode in ThemeMode.allCases {
        state.section = .tasks
        state.themeMode = mode
        render("tasks-" + mode.rawValue, content: MainWindowView(state: state, store: store, calendar: calendar))
    }
    state.themeMode = .harbor
    render("tasks-compact", width: 900, content: MainWindowView(state: state, store: store, calendar: calendar))
    state.taskLayout = .list
    render("tasks-list", content: MainWindowView(state: state, store: store, calendar: calendar))
    state.taskLayout = .board
    for mode in [ThemeMode.harbor, .dark] {
        render("task-editor-" + mode.rawValue, width: 1080, height: 800,
               content: TaskDetailEditor(task: TaskItem(label: "Review the new designs", lane: store.defaultLane, meta: RichEditorPreview.sample, workflow: .inProgress),
                                         isNew: false, store: store, theme: mode.theme, autoLog: false, onClose: {}, onDelete: {}))
    }
    render("task-editor-validation", width: 1080, height: 800,
           content: TaskDetailEditor(task: TaskItem(lane: store.defaultLane), isNew: false, store: store, theme: .harbor, autoLog: false, onClose: {}, onDelete: {}))
    for mode in ThemeMode.allCases {
        render("rich-editor-" + mode.rawValue, width: 680, height: 640,
               content: RichEditorPreview(theme: mode.theme, root: root))
    }
    render("rich-editor-selection", width: 680, height: 640,
           content: RichEditorPreview(theme: .harbor, root: root, selectText: true))
}

private struct ChecklistPreview: View {
    let theme: Theme
    @State private var controller = NoteEditorController()
    private let id = UUID()

    var body: some View {
        ContinuousNoteEditor(noteID: id, markdown: """
        # Add ons

        - [ ] Design subscription – ₹2499 / month
        - [ ] Learning subscription – ₹549
        - [ ] Movie subscription
        - [ ] 
        - [x] Cloud storage – ₹75

        - [ ] A longer item wraps under its own text and keeps the circle aligned with the first line while you keep writing.
        """, color: NSColor(theme.text), checklistAccent: NSColor(theme.accent),
        checklistInk: NSColor(theme.onAccent), checklistOutline: NSColor(theme.muted),
        controller: controller, requestFocus: false, onChange: { _ in }, onBlur: {})
        .background(theme.surface)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

private struct RichEditorPreview: View {
    let theme: Theme
    let root: URL
    var selectText = false
    @State private var controller = NoteEditorController()
    @State private var bodyText = sample
    private let id = UUID()
    static let sample = """
    ## A few small improvements
    Use **bold**, _italic_, <u>underline</u>, ~~strikethrough~~ and \u{0060}inline code\u{0060}.
    Read the [project notes](https://example.com/notes) before starting.

    - [x] Make More clickable
    - [ ] Review the new board

    > Keep the tools close and the workspace calm.

    \u{0060}\u{0060}\u{0060}swift
    let nextStep = "Keep it simple"
    print(nextStep)
    \u{0060}\u{0060}\u{0060}

    | Work | Status |
    | --- | --- |
    | Board layout | In progress |
    | Checklist polish | Done |

    ---
    Type / to insert a heading, checklist, table, date or attachment.
    """

    var body: some View {
        RichTextEditor(id: id, markdown: $bodyText, controller: controller, theme: theme, baseURL: root)
        .task {
            if selectText, let view = controller.textView {
                view.setSelectedRange((view.string as NSString).range(of: "project notes"))
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}
