import AppKit
import SwiftUI

/// Mounted only while recording. Local monitoring captures keys before menus;
/// HotKeyCenter also forwards keys that Carbon has already consumed.
struct ShortcutEventRecorder: NSViewRepresentable {
    let onShortcut: (HotKeyCenter.Shortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onShortcut = onShortcut; view.onCancel = onCancel
        view.start()
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onShortcut = onShortcut; view.onCancel = onCancel
    }

    static func dismantleNSView(_ view: RecorderView, coordinator: ()) { view.stop() }

    final class RecorderView: NSView {
        var onShortcut: ((HotKeyCenter.Shortcut) -> Void)?
        var onCancel: (() -> Void)?
        private var monitor: Any?
        private var inactiveObserver: NSObjectProtocol?
        private var windowObserver: NSObjectProtocol?

        func start() {
            HotKeyCenter.shared.recordingHandler = { [weak self] shortcut in
                guard let self, self.window?.isKeyWindow == true else { return }
                self.onShortcut?(shortcut)
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window?.isKeyWindow == true else { return event }
                if event.isARepeat { return nil }
                let shortcut = HotKeyCenter.Shortcut(event: event)
                if shortcut.keyCode == 53 && shortcut.modifiers == 0 { self.onCancel?() }
                else { self.onShortcut?(shortcut) }
                return nil
            }
            inactiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                      object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onCancel?() }
            }
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                    object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let window = note.object as? NSWindow, window === self.window else { return }
                    self.onCancel?()
                }
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) }
            if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
            monitor = nil; inactiveObserver = nil; windowObserver = nil
            HotKeyCenter.shared.recordingHandler = nil
        }
    }
}
