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
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private let state = AppState()
    private let store = Store()
    private var bar: BarPanelController?
    private var window: NSWindow?
    private var ticker: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Typo.registerBundledFonts()
        store.load()

        bar = BarPanelController(state: state) { [weak self] section in
            self?.state.section = section
            self?.showMainWindow()
        }
        bar?.show()

        showMainWindow()
        startTicker()
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

    private func showMainWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
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
        w.contentView = NSHostingView(rootView: MainWindowView(state: state, store: store))
        w.center()

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
