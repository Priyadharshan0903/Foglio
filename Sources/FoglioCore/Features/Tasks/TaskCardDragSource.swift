import AppKit
import SwiftUI

/// A native drag source provides cursor updates through the whole session,
/// including cancellation. The SwiftUI button retains keyboard/accessibility
/// actions and its context menu; this overlay handles only left-button events.
struct TaskCardDragSource: NSViewRepresentable {
    let taskID: UUID
    let onOpen: () -> Void
    var onDragChanged: (UUID?) -> Void = { _ in }

    func makeNSView(context: Context) -> TaskCardDragView {
        let view = TaskCardDragView()
        view.taskID = taskID
        view.onOpen = onOpen
        view.onDragChanged = onDragChanged
        return view
    }

    func updateNSView(_ view: TaskCardDragView, context: Context) {
        view.taskID = taskID
        view.onOpen = onOpen
        view.onDragChanged = onDragChanged
    }
}

final class TaskCardDragView: NSView, NSDraggingSource {
    var taskID = UUID()
    var onOpen: () -> Void = {}
    var onDragChanged: (UUID?) -> Void = { _ in }
    private var pressPoint: NSPoint?
    private(set) var isDragging = false
    var isGrabbed: Bool { isDragging || pressPoint != nil }
    private var cursorTracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)),
              let type = NSApplication.shared.currentEvent?.type,
              [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(type) else { return nil }
        return self
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: isGrabbed ? .closedHand : .openHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
                                  owner: self)
        addTrackingArea(area)
        cursorTracking = area
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor() }
    override func mouseEntered(with event: NSEvent) { updateCursor() }
    override func mouseMoved(with event: NSEvent) { updateCursor() }
    override func mouseExited(with event: NSEvent) {
        if !isGrabbed { NSCursor.arrow.set() }
    }
    private func updateCursor() { (isGrabbed ? NSCursor.closedHand : NSCursor.openHand).set() }

    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil)
        updateCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let pressPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - pressPoint.x, point.y - pressPoint.y) >= 4 else { return }
        guard let root = window?.contentView,
              let bitmap = root.bitmapImageRepForCachingDisplay(in: convert(bounds, to: root)) else { return }
        root.cacheDisplay(in: convert(bounds, to: root), to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem())
        item.setDraggingFrame(bounds, contents: image)
        isDragging = true
        updateCursor()
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressPoint = nil
            if isDragging || bounds.contains(convert(event.locationInWindow, from: nil)) {
                updateCursor()
            } else {
                NSCursor.arrow.set()
            }
        }
        guard !isDragging, pressPoint != nil,
              bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onOpen()
    }

    func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString("foglio-task:\(taskID.uuidString)", forType: .string)
        return item
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // SwiftUI's transferable destination may negotiate a copy operation;
        // the board always updates the existing task rather than duplicating it.
        context == .withinApplication ? [.copy, .move] : []
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        isDragging = true
        onDragChanged(taskID)
        updateCursor()
    }
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) { updateCursor() }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        onDragChanged(nil)
        pressPoint = nil
        if let window, visibleRect.contains(convert(window.convertPoint(fromScreen: screenPoint), from: nil)) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
        window?.invalidateCursorRects(for: self)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
