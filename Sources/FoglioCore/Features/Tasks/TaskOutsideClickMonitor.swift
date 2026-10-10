import AppKit
import SwiftUI

struct TaskOutsideClickContext {
    let point: NSPoint
    let parentFrame: NSRect
    let editorFrame: NSRect
    let isParentOrEditor: Bool
    let isFrontSheet: Bool
    let hasNestedSheet: Bool

    var shouldDismiss: Bool {
        isParentOrEditor && isFrontSheet && !hasNestedSheet &&
            parentFrame.contains(point) && !editorFrame.contains(point)
    }
}

/// Native sheets block their parent window's controls. Watch only clicks in
/// that parent, consume the dismissal click, and leave auxiliary windows alone.
struct TaskOutsideClickMonitor: NSViewRepresentable {
    let enabled: Bool
    let onOutside: () -> Void

    func makeNSView(context: Context) -> TaskOutsideClickView {
        let view = TaskOutsideClickView()
        view.enabled = enabled
        view.onOutside = onOutside
        return view
    }

    func updateNSView(_ view: TaskOutsideClickView, context: Context) {
        view.onOutside = onOutside
        view.enabled = enabled
    }

    static func dismantleNSView(_ view: TaskOutsideClickView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class TaskOutsideClickView: NSView {
    var enabled = false { didSet { updateMonitoring() } }
    var onOutside: () -> Void = {}
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitoring()
    }

    private func updateMonitoring() {
        stopMonitoring()
        guard enabled, window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Do not treat field focus, opening another window, or app deactivation
    /// as a request to abandon a draft. Nested sheets include alerts and pickers.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard enabled, [.leftMouseDown, .rightMouseDown].contains(event.type),
              let sheet = window, let parent = sheet.sheetParent,
              let clickedWindow = event.window else { return event }
        let context = TaskOutsideClickContext(
            point: clickedWindow.convertPoint(toScreen: event.locationInWindow),
            parentFrame: parent.frame, editorFrame: sheet.frame,
            isParentOrEditor: clickedWindow === parent || clickedWindow === sheet,
            isFrontSheet: parent.attachedSheet === sheet,
            hasNestedSheet: sheet.attachedSheet != nil
        )
        guard context.shouldDismiss else { return event }
        onOutside()
        return nil
    }

    deinit { stopMonitoring() }
}
