import AppKit
import SwiftUI
@testable import FoglioCore

/// Marketing screenshots use fictional sample content in an isolated library.
/// No calendar rendering, account access, or real user data is involved.
@MainActor
func renderLandingAssetsIfRequested() {
    guard let path = ProcessInfo.processInfo.environment["FOGLIO_LANDING_ASSETS"] else { return }
    Typo.registerBundledFonts()
    let directory = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foglio-marketing-\(UUID())")
    let suite = "FoglioMarketing-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }
    let state = AppState(defaults: defaults)
    let store = Store(root: root); store.load()
    let calendar = CalendarSource()
    let note = Note(title: "A little room to think", body: """
    Every good day starts with a little space.

    ## The studio launch
    A place for the ideas, details, and small things that make it ours.

    ### What matters this week
    - [x] Find the direction
    - [ ] Refine the first collection
    - [ ] Make something worth sharing

    ## A thought worth keeping
    We don't need to do everything. Just the next thing, well.

    > Leave a little room for the unexpected.

    ### On the desk
    - Sketches for the new identity
    - A playlist for the afternoon
    - Coffee with the team on Friday
    """, folder: .scratch)
    store.upsert(Note(title: "The next chapter", body: "Ideas for the season ahead.", folder: .scratch))
    store.upsert(Note(title: "Friday catch-up", body: "A few things to talk through.\n- [ ] Review the first sketches\n- [ ] Plan next week", folder: .scratch))
    store.upsert(Note(title: "Things worth remembering", body: "Small details make a difference.", folder: .scratch))
    store.upsert(note)
    state.activeNoteId = note.id
    state.folderFilter = .scratch
    let work = store.addLane(named: "Studio")!
    for (title, status) in [
        ("Explore the new direction", TaskWorkflow.backlog), ("Gather references", .backlog),
        ("Refine the first collection", .todo), ("Share the launch notes", .todo),
        ("Make time for a walk", .todo), ("Sketch the first concepts", .inProgress),
        ("Design the welcome page", .inProgress), ("Find the direction", .done),
        ("Plan the studio launch", .done)
    ] {
        store.addTask(TaskItem(label: title, lane: work, meta: title.contains("Sketch") ? "Keep the first version simple." : "",
                               done: status == .done, workflow: status))
    }
    func render<Content: View>(_ name: String, width: Double = 1440, height: Double = 940, content: Content) {
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
            try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        }
        window.close()
    }
    for mode in ThemeMode.allCases {
        state.section = .notes; state.themeMode = mode
        render("notes-" + mode.rawValue, content: MainWindowView(state: state, store: store, calendar: calendar))
    }
    state.section = .tasks; state.themeMode = .ember
    render("tasks-ember", content: MainWindowView(state: state, store: store, calendar: calendar))
    render("editor-ember", width: 1080, height: 800,
           content: TaskDetailEditor(task: TaskItem(label: "Design the welcome page", lane: work,
                                                   meta: "## Start with the essentials\nA **clear idea**, a little _personality_, and room to breathe.\n\n- [x] Find the direction\n- [ ] Refine the details\n- [ ] Share the first version\n\n> Small things, done thoughtfully.\n\n| Detail | Next step |\n| --- | --- |\n| Writing | Keep it clear |\n| Design | Make room |", workflow: .inProgress),
                                     isNew: false, store: store, theme: .ember, autoLog: false, onClose: {}, onDelete: {}))
    print("Landing-page screenshots saved to \(path)")
}
