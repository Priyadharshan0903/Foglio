import AppKit
import SwiftUI

/// A native drag source provides cursor updates through the whole session,
/// including cancellation. The SwiftUI button retains keyboard/accessibility
/// actions and its context menu; this overlay handles only left-button events.
struct TaskCardDragSource: NSViewRepresentable {
    let taskID: UUID
    let onOpen: () -> Void
    var onDragChanged: (UUID?) -> Void = { _ in }
    var onLift: (CGSize) -> Void = { _ in }

    func makeNSView(context: Context) -> TaskCardDragView {
        let view = TaskCardDragView()
        view.taskID = taskID
        view.onOpen = onOpen
        view.onDragChanged = onDragChanged
        view.onLift = onLift
        return view
    }

    func updateNSView(_ view: TaskCardDragView, context: Context) {
        view.taskID = taskID
        view.onOpen = onOpen
        view.onDragChanged = onDragChanged
        view.onLift = onLift
    }
}

final class TaskCardDragView: NSView, NSDraggingSource {
    var taskID = UUID()
    var onOpen: () -> Void = {}
    var onDragChanged: (UUID?) -> Void = { _ in }
    var onLift: (CGSize) -> Void = { _ in }
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
        let image = TaskCardDragImage.make(bitmap: bitmap, size: bounds.size)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem())
        item.setDraggingFrame(TaskCardDragImage.frame(for: bounds), contents: image)
        isDragging = true
        updateCursor()
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.draggingFormation = .none
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
        onLift(bounds.size)
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

enum TaskCardDragImage {
    static let margin: CGFloat = 10
    static func frame(for bounds: CGRect) -> CGRect { bounds.insetBy(dx: -margin, dy: -margin) }

    static func make(bitmap: NSBitmapImageRep, size: CGSize) -> NSImage {
        // Bitmap pixels may be 2x the point size on Retina displays. Explicit
        // logical dimensions keep AppKit's preview at the original card size.
        bitmap.size = size
        let card = NSImage(size: size)
        card.addRepresentation(bitmap)
        card.size = size
        let previewSize = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
        return NSImage(size: previewSize, flipped: false) { rect in
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
            shadow.shadowBlurRadius = 7
            shadow.shadowOffset = CGSize(width: 0, height: -2)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            card.draw(in: rect.insetBy(dx: margin, dy: margin))
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }
}
