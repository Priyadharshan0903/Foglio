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
    private var meetingAlert: MeetingAlertPanel?
    private var window: NSWindow?
    private var ticker: Timer?
    private var calendarTimer: Timer?
    private var lastBadge: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Debug.log("didFinishLaunching")
        Typo.registerBundledFonts()
        Debug.log("fonts: geist=\(Typo.geistAvailable) sample=\(Typo.describeResolved())")
        store.load()
        calendar.refreshAccess()
        calendar.resumeWatching()
        startCalendarRefresh()

        bar = BarPanelController(state: state) { [weak self] section in
            self?.state.section = section
            self?.showMainWindow()
        }
        meetingAlert = MeetingAlertPanel(state: state)

        // Under FOGLIO_DEBUG, lay the (hidden) bar out at launch so its geometry
        // can be inspected without having to close the window first — automation
        // permission is unreliable here, so this is the practical way to check it.
        if ProcessInfo.processInfo.environment["FOGLIO_DEBUG"] != nil {
            bar?.applyEdge()
        }

        installMenu()
        registerHotKeys()
        showMainWindow()
        startTicker()
        observeBarEdge()
        Debug.log("launched; NSApp.windows=\(NSApp.windows.count) visible=\(NSApp.windows.filter(\.isVisible).count) edge=\(state.barEdge.rawValue)")
    }

    /// The bar-edge setting has to move (and re-measure) an AppKit panel, which
    /// SwiftUI can't do for us. `withObservationTracking` fires once, so it
    /// re-arms each time.
    private func observeBarEdge() {
        withObservationTracking {
            _ = state.barEdge
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.bar?.applyEdge()
                    self?.observeBarEdge()
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

    /// Meetings move during the day, so re-read every 15 minutes. Cheap for a
    /// local file; a single conditional GET for a subscription URL.
    private func startCalendarRefresh() {
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.calendar.refresh() }
            }
        }
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.state.tick() {
                    self.store.addLog(LogEntry(text: "Focus block complete", kind: .focus))
                }
                self.refreshMeetingNudge()
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

    /// Keeps the calendar badge and the meeting nudge in step, once a second.
    ///
    /// The nudge follows the bar: it only makes sense as something you glance at
    /// while working, so it hides whenever the main window is up.
    private func refreshMeetingNudge() {
        guard let bar, let meetingAlert else { return }

        let badge = bar.isVisible ? calendar.badgeText : nil
        if badge != lastBadge {
            lastBadge = badge
            bar.updateBadge(badge)
        }

        guard bar.isVisible,
              calendar.isMeetingSoon(within: state.meetingLeadMinutes),
              let event = calendar.upNext,
              !state.dismissedMeetings.contains(event.id)
        else {
            if meetingAlert.isShowing { meetingAlert.hide() }
            return
        }

        guard !meetingAlert.isShowing(event) else { return }

        meetingAlert.show(
            event: event,
            barFrame: bar.frame,
            onJoin: { [weak self] in
                if let url = MeetingAlertView.joinURL(for: event) { NSWorkspace.shared.open(url) }
                self?.state.dismissMeeting(event.id)
                self?.meetingAlert?.hide()
            },
            onTakeNotes: { [weak self] in
                self?.takeNotes(on: event)
                self?.state.dismissMeeting(event.id)
                self?.meetingAlert?.hide()
            },
            onDismiss: { [weak self] in
                self?.state.dismissMeeting(event.id)
                self?.meetingAlert?.hide()
            }
        )
    }

    /// `alertNote` (:929) — a note titled after the meeting, ready to type into.
    private func takeNotes(on event: DayEvent) {
        let note = Note(
            title: event.title,
            body: Markdown.serialize([
                .h2("\(Clock.hhmm(event.start)) · \(event.location)"),
                .paragraph(""),
            ]),
            folder: .scratch
        )
        store.upsert(note)
        state.section = .notes
        state.activeNoteId = note.id
        state.activeBlock = 1
        showMainWindow()
    }

    private func showMainWindow() {
        bar?.hide()
        meetingAlert?.hide()

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
        Debug.log("showMainWindow: frame=\(w.frame) visible=\(w.isVisible)")
    }
}
