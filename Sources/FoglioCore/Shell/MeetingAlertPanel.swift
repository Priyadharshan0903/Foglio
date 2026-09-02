import AppKit
import SwiftUI

/// Hosts the meeting nudge in its own panel, next to the bar.
///
/// It can't live inside the bar's panel: that one is sized exactly to the strip
/// so it never swallows clicks meant for windows behind it, and a 288pt card
/// would undo exactly that. A second panel keeps both properties.
@MainActor
final class MeetingAlertPanel {
    private let panel: BarPanel
    private let state: AppState
    private var host: NSHostingView<AnyView>?

    /// The event currently on screen, so it isn't rebuilt every tick.
    private var showingEventId: String?

    init(state: AppState) {
        self.state = state
        panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 288, height: 160),
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

    func hide() {
        panel.orderOut(nil)
        showingEventId = nil
    }

    /// Shows the nudge for `event`, anchored beside `barFrame`.
    func show(
        event: DayEvent,
        barFrame: NSRect,
        onJoin: @escaping () -> Void,
        onTakeNotes: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let view = MeetingAlertView(
            state: state,
            event: event,
            onJoin: onJoin,
            onTakeNotes: onTakeNotes,
            onDismiss: onDismiss
        )

        if let host {
            host.rootView = AnyView(view)
        } else {
            let created = NSHostingView(rootView: AnyView(view))
            panel.contentView = created
            host = created
        }

        guard let host else { return }
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        if fitting.width > 1, fitting.height > 1 { panel.setContentSize(fitting) }

        position(besides: barFrame)
        panel.orderFrontRegardless()
        showingEventId = event.id
    }

    var isShowing: Bool { panel.isVisible }

    func isShowing(_ event: DayEvent) -> Bool {
        panel.isVisible && showingEventId == event.id
    }

    /// Sits beside the strip, flipping to whichever side has room.
    private func position(besides barFrame: NSRect) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let gap: CGFloat = 9

        var origin = NSPoint.zero

        if state.barEdge.isHorizontal {
            // Under a top-docked bar, left-aligned but kept on screen.
            origin.x = min(barFrame.minX, visible.maxX - size.width - gap)
            origin.y = barFrame.minY - size.height - gap
        } else {
            let toTheRight = barFrame.maxX + gap
            let toTheLeft = barFrame.minX - size.width - gap
            origin.x = (toTheRight + size.width) <= visible.maxX ? toTheRight : toTheLeft
            // Vertically centred on the bar, clamped inside the screen.
            origin.y = min(
                max(barFrame.midY - size.height / 2, visible.minY + gap),
                visible.maxY - size.height - gap
            )
        }

        panel.setFrameOrigin(origin)
    }
}
