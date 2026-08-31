import AppKit
import SwiftUI

/// Entry point, called from the thin `Foglio` executable target.
///
/// Everything lives in this library rather than the executable so the test
/// target can link it without dragging in `@main` — linking an executable into
/// a test host starts the AppKit run loop and hangs the test runner.
public func runFoglio() -> Never {
    // Top-level code in the executable already runs on the main thread; this
    // just tells the compiler so.
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.delegate = AppDelegate.shared // NSApplication.delegate is weak
        app.setActivationPolicy(.regular)
        app.run()
    }
    exit(0)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = AppDelegate()

    private let state = AppState()
    private let store = Store()
    private let calendar = CalendarSource()
    private var bar: BarPanelController?
    private var window: NSWindow?
    private var ticker: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Typo.registerBundledFonts()
        store.load()
        calendar.refreshAccess()

        bar = BarPanelController(state: state) { [weak self] section in
            self?.state.section = section
            self?.showMainWindow()
        }

        installMenu()
        registerHotKeys()
        showMainWindow()
        startTicker()
        observeBarSide()
    }

    /// The bar-edge setting has to move an AppKit panel, which SwiftUI can't do
    /// for us. `withObservationTracking` fires once, so it re-arms each time.
    private func observeBarSide() {
        withObservationTracking {
            _ = state.barSide
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.bar?.reposition()
                    self?.observeBarSide()
                }
            }
        }
    }

    private func installMenu() {
        MainMenu.install(
            onQuickCapture: { [weak self] in self?.go(.capture) },
            onNewNote: { [weak self] in self?.newScratchNote() },
            onTasks: { [weak self] in self?.go(.tasks) },
            onSearch: { [weak self] in
                self?.showMainWindow()
                self?.state.searchFocusRequests += 1
            },
            onSettings: { [weak self] in self?.go(.settings) }
        )
    }

    private func registerHotKeys() {
        HotKeyCenter.shared.register(.quickCapture) { [weak self] in self?.go(.capture) }
        HotKeyCenter.shared.register(.tasks) { [weak self] in self?.go(.tasks) }
        HotKeyCenter.shared.register(.newNote) { [weak self] in self?.newScratchNote() }
    }

    /// Bring the window forward on a given section.
    private func go(_ section: Section) {
        state.section = section
        showMainWindow()
    }

    /// ⌘⇧N — new note in Scratch (:1225).
    private func newScratchNote() {
        let note = store.newNote(in: .scratch)
        state.section = .notes
        state.folderFilter = .scratch
        state.activeNoteId = note.id
        state.activeBlock = 0
        showMainWindow()
    }

    /// Escape sends the window away but keeps the bar and the app alive (:1229).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.state.tick() {
                    self.store.addLog(LogEntry(text: "Focus block complete", kind: .focus))
                }
            }
        }
    }

    // MARK: - Bar / window are alternates, never both
    //
    // The strip exists to be reachable when the window isn't there. Showing
    // both at once just duplicates the same five destinations, so the bar hides
    // whenever the window is up and comes back when it goes away.

    func windowWillClose(_ notification: Notification) {
        bar?.show()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        bar?.show()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        bar?.hide()
    }

    private func showMainWindow() {
        bar?.hide()

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "Foglio"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 900, height: 700)
        w.contentView = NSHostingView(rootView: MainWindowView(state: state, store: store, calendar: calendar))
        w.center()

        w.delegate = self
        // Escape clears a search before it closes the window.
        w.onCancel = { [weak self] in
            guard let self, !self.state.search.isEmpty else { return false }
            self.state.search = ""
            return true
        }

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
