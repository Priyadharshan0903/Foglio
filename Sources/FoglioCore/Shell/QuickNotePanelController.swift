import AppKit
import SwiftUI

/// A borderless panel that wants keyboard focus, unlike `BarPanel` which
/// explicitly refuses it. `NSWindow.canBecomeKey` defaults to false for a
/// borderless window, so a plain `.borderless` panel would never let the
/// `TextEditor` inside it become first responder without this override.
final class QuickNoteWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Hosts the quick-notes card in its own panel, next to the bar — the same
/// "second panel beside the strip" shape as `MeetingAlertPanel`, but this one
/// needs to accept typing, so it's a `QuickNoteWindow` rather than a `BarPanel`.
@MainActor
final class QuickNotePanelController {
    private let panel: QuickNoteWindow
    private let state: AppState
    private let store: Store
    private var host: NSHostingView<QuickNotePanel>?
    private var outsideClickMonitor: Any?

    /// How far the card slides in from (and back out towards) the bar on
    /// open/close, in points.
    private let slide: CGFloat = 8

    init(state: AppState, store: Store) {
        self.state = state
        self.store = store
        panel = QuickNoteWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 260),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
    }

    var isShowing: Bool { panel.isVisible }

    /// Clicking the Notes icon again while the card is open closes it, same as
    /// clicking away from it.
    func toggle(besides barFrame: NSRect, pointerAt anchor: CGPoint, onOpenLarge: @escaping () -> Void) {
        if isShowing {
            hide()
        } else {
            show(besides: barFrame, pointerAt: anchor, onOpenLarge: onOpenLarge)
        }
    }

    /// Fades and slides the card back towards the bar, then orders it out.
    func hide() {
        guard panel.isVisible else { return }
        removeOutsideClickMonitor()

        let edge = currentPointerEdge
        var retreat = panel.frame.origin
        switch edge {
        case .top: retreat.y += slide
        case .left: retreat.x -= slide
        case .right: retreat.x += slide
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(retreat)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
            }
        }
    }

    private var currentPointerEdge: QuickNotePointerEdge = .top

    private func show(besides barFrame: NSRect, pointerAt anchor: CGPoint, onOpenLarge: @escaping () -> Void) {
        // Which edge the bar is docked to determines which edge the card
        // points back at it from — see `pointerEdge(for:)`.
        let edge = Self.pointerEdge(for: state.barEdge)
        currentPointerEdge = edge

        setRootView(edge: edge, pointerOffset: 0, onOpenLarge: onOpenLarge)
        guard let host else { return }
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        if fitting.width > 1, fitting.height > 1 { panel.setContentSize(fitting) }

        let finalOrigin = origin(besides: barFrame)
        let offset = pointerOffset(edge: edge, origin: finalOrigin, anchor: anchor, size: panel.frame.size)
        // The offset needs the final, measured size, so the view is rebuilt
        // once more with the real aim point — this doesn't change layout, so
        // no second measure pass is needed.
        setRootView(edge: edge, pointerOffset: offset, onOpenLarge: onOpenLarge)

        var startOrigin = finalOrigin
        switch edge {
        case .top: startOrigin.y += slide
        case .left: startOrigin.x -= slide
        case .right: startOrigin.x += slide
        }

        panel.alphaValue = 0
        panel.setFrame(NSRect(origin: startOrigin, size: panel.frame.size), display: false)
        // `makeKeyAndOrderFront`, not `orderFrontRegardless` — the whole point
        // here (unlike the bar and the meeting nudge) is that typing works.
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(finalOrigin)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        }

        installOutsideClickMonitor()
    }

    private func setRootView(edge: QuickNotePointerEdge, pointerOffset: CGFloat, onOpenLarge: @escaping () -> Void) {
        let view = QuickNotePanel(
            state: state,
            store: store,
            pointerEdge: edge,
            pointerOffset: pointerOffset,
            onOpenLarge: { [weak self] in
                self?.hide()
                onOpenLarge()
            },
            onCollapse: { [weak self] in self?.hide() }
        )
        if let host {
            host.rootView = view
        } else {
            let created = NSHostingView(rootView: view)
            panel.contentView = created
            host = created
        }
    }

    /// A left/right-docked bar almost always has room on its outward side, so
    /// the pointer points straight at it; the rare screen-edge flip in
    /// `origin(besides:)` is a fallback we don't bother re-aiming for.
    private static func pointerEdge(for barEdge: BarEdge) -> QuickNotePointerEdge {
        switch barEdge {
        case .top: .top
        case .left: .left
        case .right: .right
        }
    }

    /// Sits beside the strip, flipping to whichever side has room — identical
    /// positioning rule to `MeetingAlertPanel.position(besides:)`.
    private func origin(besides barFrame: NSRect) -> NSPoint {
        guard let screen = NSScreen.main else { return panel.frame.origin }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let gap: CGFloat = 9

        var origin = NSPoint.zero

        if state.barEdge.isHorizontal {
            origin.x = min(barFrame.minX, visible.maxX - size.width - gap)
            origin.y = barFrame.minY - size.height - gap
        } else {
            let toTheRight = barFrame.maxX + gap
            let toTheLeft = barFrame.minX - size.width - gap
            origin.x = (toTheRight + size.width) <= visible.maxX ? toTheRight : toTheLeft
            origin.y = min(
                max(barFrame.midY - size.height / 2, visible.minY + gap),
                visible.maxY - size.height - gap
            )
        }

        return origin
    }

    /// Where along the card's pointer edge to aim the notch — at the Notes
    /// icon itself, not just the middle of the whole strip.
    private func pointerOffset(edge: QuickNotePointerEdge, origin: NSPoint, anchor: CGPoint, size: NSSize) -> CGFloat {
        switch edge {
        case .top:
            return anchor.x - origin.x
        case .left, .right:
            // AppKit's y grows upward from the card's bottom; the shape
            // measures from the card's top, in SwiftUI's downward-growing space.
            return (origin.y + size.height) - anchor.y
        }
    }

    /// Closes the card on a click anywhere outside it — a global monitor sees
    /// clicks in other apps too, which a local `NSWindow` click-outside check
    /// wouldn't.
    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}
