import AppKit
@testable import FoglioCore

@MainActor
func taskEditorTests() {
    Check.suite("Task cards — click and drag lifecycle") {
        let card = TaskCardDragView(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
        let id = UUID()
        card.taskID = id
        var opens = 0
        var activeDrag: UUID?
        card.onDragChanged = { activeDrag = $0 }
        card.onOpen = { opens += 1 }
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                              windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let down = event(.leftMouseDown, NSPoint(x: 30, y: 30))
        let up = event(.leftMouseUp, NSPoint(x: 30, y: 30))
        card.mouseDown(with: down)
        Check.expect(card.isGrabbed, "pressing a card immediately shows the grabbing state")
        card.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 31, y: 31)))
        card.mouseUp(with: up)
        Check.expect(!card.isGrabbed, "a regular click clears the grabbing state")
        Check.equal(opens, 1, "small pointer movements still open a task once")
        card.mouseDown(with: down)
        card.mouseUp(with: event(.leftMouseUp, NSPoint(x: 350, y: 30)))
        Check.equal(opens, 1, "releasing outside the card cancels the click")
        Check.equal(card.pasteboardItem().string(forType: .string), "foglio-task:\(id.uuidString)",
                    "native drags retain the board's existing transferable task payload")
        let session = NSDraggingSession()
        let operations = card.draggingSession(session, sourceOperationMaskFor: .withinApplication)
        Check.expect(operations.contains(.move) && operations.contains(.copy), "the board can negotiate a local drop")
        Check.expect(card.draggingSession(session, sourceOperationMaskFor: .outsideApplication).isEmpty,
                     "task cards cannot be moved into another application")
        for operation in [NSDragOperation.move, []] {
            card.mouseDown(with: down)
            card.draggingSession(session, willBeginAt: .zero)
            Check.equal(activeDrag, id, "destinations receive the native drag source identity")
            Check.expect(card.isDragging, "starting a drag switches to the grabbing state")
            card.mouseUp(with: up)
            Check.equal(opens, 1, "dragging does not also open the task editor")
            card.draggingSession(session, endedAt: .zero, operation: operation)
            Check.expect(activeDrag == nil, "drop and cancellation clear destination insertion markers")
            Check.expect(!card.isDragging, "both a completed drop and cancellation clear the grabbing state")
            Check.expect(!card.isGrabbed, "ending or cancelling a drag releases the grab cursor")
            card.mouseUp(with: up)
            Check.equal(opens, 1, "the release after a finished drag cannot open the editor")
        }
    }

    Check.suite("Task editor — outside-click preference") {
        let suite = "FoglioTaskCloseTest-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        Check.expect(state.closeTaskOnOutsideClick, "outside-click dismissal is enabled by default")
        state.closeTaskOnOutsideClick = false
        Check.expect(!AppState(defaults: defaults).closeTaskOnOutsideClick, "opting out survives a relaunch")
        state.closeTaskOnOutsideClick = true
        Check.expect(AppState(defaults: defaults).closeTaskOnOutsideClick, "opting back in survives a relaunch")
    }

    Check.suite("Task editor — outside-click boundaries") {
        let parent = NSRect(x: 100, y: 100, width: 1000, height: 800)
        let editor = NSRect(x: 260, y: 220, width: 680, height: 620)
        func context(_ point: NSPoint, related: Bool = true, front: Bool = true, nested: Bool = false) -> TaskOutsideClickContext {
            TaskOutsideClickContext(point: point, parentFrame: parent, editorFrame: editor,
                                    isParentOrEditor: related, isFrontSheet: front, hasNestedSheet: nested)
        }
        for point in [NSPoint(x: 120, y: 120), NSPoint(x: 250, y: 500), NSPoint(x: 1000, y: 500)] {
            Check.expect(context(point).shouldDismiss, "clicks around the card in the parent window request dismissal")
        }
        for point in [NSPoint(x: 260, y: 220), NSPoint(x: 300, y: 800), NSPoint(x: 500, y: 500)] {
            Check.expect(!context(point).shouldDismiss, "title, toolbar, and editor clicks keep the card open")
        }
        let outside = NSPoint(x: 120, y: 120)
        Check.expect(!context(outside, related: false).shouldDismiss, "menus and auxiliary windows cannot dismiss the card")
        Check.expect(!context(outside, front: false).shouldDismiss, "a different foreground sheet cannot dismiss this card")
        Check.expect(!context(outside, nested: true).shouldDismiss, "attachment pickers and confirmation sheets protect the draft")
        Check.expect(!context(NSPoint(x: 50, y: 50)).shouldDismiss, "clicking elsewhere on the desktop does not discard a task")
    }

    // Requires a WindowServer session. Keep the native dispatch check runnable
    // on a desktop, while the boundary and preference tests also run headlessly.
    guard !NSScreen.screens.isEmpty else {
        print("  skip native task-sheet dispatch: no WindowServer screen available")
        return
    }
    Check.suite("Task editor — native sheet outside clicks") {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1000, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                             styleMask: [.titled], backing: .buffered, defer: false)
        let other = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 200, height: 200),
                             styleMask: [.titled], backing: .buffered, defer: false)
        for window in [parent, sheet, other] { window.isReleasedWhenClosed = false }
        let watcher = TaskOutsideClickView()
        sheet.contentView = watcher
        var closes = 0
        watcher.enabled = true
        watcher.onOutside = { closes += 1 }
        parent.orderFront(nil)
        parent.beginSheet(sheet)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        defer {
            watcher.stopMonitoring()
            parent.endSheet(sheet)
            for window in [sheet, parent, other] { window.close() }
        }
        Check.expect(sheet.sheetParent === parent, "the test uses an attached native sheet")
        @MainActor func click(_ window: NSWindow, _ point: NSPoint, type: NSEvent.EventType = .leftMouseDown) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                              clickCount: 1, pressure: 1)!
        }
        let outside = click(parent, NSPoint(x: 20, y: 20))
        let inside = click(sheet, NSPoint(x: 340, y: 310))
        Check.expect(watcher.handle(inside) != nil, "clicking inside the editor does not close it")
        Check.equal(closes, 0, "editor controls preserve the draft")
        Check.expect(watcher.handle(click(other, NSPoint(x: 20, y: 20))) != nil,
                     "auxiliary windows such as formatting popovers are ignored")
        Check.expect(watcher.handle(outside) == nil, "the outside click is consumed instead of reaching the board")
        Check.equal(closes, 1, "a click on the parent background requests dismissal")
        NSApplication.shared.sendEvent(outside)
        Check.equal(closes, 2, "the installed event monitor receives an actual parent-window event")

        watcher.enabled = false
        Check.expect(watcher.handle(outside) != nil, "opting out leaves outside clicks alone")
        NSApplication.shared.sendEvent(outside)
        Check.equal(closes, 2, "disabled monitoring does not request dismissal")
        watcher.enabled = true
        let alert = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
                             styleMask: [.titled], backing: .buffered, defer: false)
        alert.isReleasedWhenClosed = false
        sheet.beginCriticalSheet(alert)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        Check.expect(sheet.attachedSheet === alert, "a picker or confirmation can attach to the editor")
        Check.expect(watcher.handle(outside) != nil, "nested pickers and confirmations prevent outside dismissal")
        Check.equal(closes, 2, "an outside click cannot interrupt the nested sheet")
        sheet.endSheet(alert)
        alert.close()
        watcher.stopMonitoring()
        NSApplication.shared.sendEvent(outside)
        Check.equal(closes, 2, "dismantling the editor removes its monitor")
    }
}
