import AppKit
import SwiftUI

/// The floating strip's window.
///
/// `.nonactivatingPanel` plus `canBecomeKey == false` is what keeps the bar from
/// stealing focus out of whatever you were typing in — the entire point of the
/// design. Buttons still receive clicks; only keyboard focus is refused.
final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BarPanelController {
    private let panel: BarPanel
    private let state: AppState
    private var host: NSHostingView<BarView>!
    private var observer: NSObjectProtocol?

    /// Distance from the pointer to the panel's origin when the drag began.
    /// Nil when no drag is in progress.
    private var grabOffset: CGSize?

    /// Gap between the strip and the screen edge it's docked to.
    private let inset: CGFloat = 12

    private var onPick: ((Section) -> Void)?

    /// Where the strip currently is, for anchoring the meeting nudge.
    var frame: NSRect { panel.frame }

    /// Re-renders the strip with a new badge value.
    func updateBadge(_ badge: String?) {
        guard let onPick else { return }
        host.rootView = BarView(
            state: state,
            onPick: onPick,
            drag: BarView.DragHandlers(
                onChanged: { [weak self] translation in self?.drag(by: translation) },
                onEnded: { [weak self] in self?.endDrag() }
            ),
            meetingBadge: badge
        )
    }

    init(state: AppState, onPick: @escaping (Section) -> Void) {
        self.state = state
        self.onPick = onPick

        panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 48, height: 260),
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
        panel.hasShadow = false

        // Built after init so the callbacks can capture self.
        host = NSHostingView(rootView: BarView(state: state, onPick: onPick, drag: nil))
        panel.contentView = host
        host.rootView = BarView(
            state: state,
            onPick: onPick,
            drag: BarView.DragHandlers(
                onChanged: { [weak self] translation in self?.drag(by: translation) },
                onEnded: { [weak self] in self?.endDrag() }
            )
        )

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyEdge() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Visibility

    func show() {
        applyEdge()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - Layout

    /// Re-measures (the axis may have flipped) and re-docks.
    func applyEdge() {
        // The SwiftUI layout for a new axis isn't ready until the next runloop.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.resize()
                self.reposition()
            }
        }
    }

    private func resize() {
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        Debug.log("resize edge=\(state.barEdge.rawValue) fitting=\(fitting) hostFrame=\(host.frame)")
        guard fitting.width > 1, fitting.height > 1 else { return }
        panel.setContentSize(fitting)
    }

    func reposition() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size

        var origin = NSPoint.zero
        switch state.barEdge {
        case .left:
            origin.x = visible.minX + inset
            origin.y = alongVertical(visible: visible, height: size.height)
        case .right:
            origin.x = visible.maxX - size.width - inset
            origin.y = alongVertical(visible: visible, height: size.height)
        case .top:
            origin.y = visible.maxY - size.height - inset
            origin.x = alongHorizontal(visible: visible, width: size.width)
        }
        panel.setFrameOrigin(origin)
        Debug.log("reposition edge=\(state.barEdge.rawValue) origin=\(origin) size=\(size) visible=\(visible) onScreen=\(panel.isVisible)")
    }

    /// `barOffset` is measured from the top down, which reads more naturally
    /// than AppKit's bottom-up origin when it's persisted and reasoned about.
    private func alongVertical(visible: NSRect, height: CGFloat) -> CGFloat {
        let travel = max(visible.height - height, 0)
        let fromTop = travel * state.barOffset
        return (visible.maxY - height - fromTop).clamped(visible.minY, visible.maxY - height)
    }

    private func alongHorizontal(visible: NSRect, width: CGFloat) -> CGFloat {
        let travel = max(visible.width - width, 0)
        return (visible.minX + travel * state.barOffset).clamped(visible.minX, visible.maxX - width)
    }

    // MARK: - Dragging

    /// Follows the pointer in absolute screen coordinates.
    ///
    /// Deliberately ignores the gesture's own `translation`: that is measured in
    /// the view's coordinate space, and the view moves with the panel as it is
    /// dragged, so each frame's translation is computed against an origin that
    /// just moved. That feedback loop is what made the bar flicker. The pointer's
    /// screen position doesn't move when the window does, so it's stable.
    private func drag(by translation: CGSize) {
        let mouse = NSEvent.mouseLocation

        if grabOffset == nil {
            let origin = panel.frame.origin
            grabOffset = CGSize(width: mouse.x - origin.x, height: mouse.y - origin.y)
        }
        guard let offset = grabOffset else { return }

        panel.setFrameOrigin(NSPoint(x: mouse.x - offset.width, y: mouse.y - offset.height))
    }

    /// Docks to whichever edge the strip ended up nearest, remembering how far
    /// along that edge it was dropped.
    private func endDrag() {
        // SwiftUI delivers a gesture-end when the panel is re-ordered even
        // though nothing moved. Without this guard that phantom end could
        // re-dock the bar from whatever frame it happened to have.
        guard grabOffset != nil else { return }
        grabOffset = nil

        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = panel.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)

        let edge = BarEdge.docking(for: center, in: visible)

        // Keep where it was dropped along the edge rather than re-centring.
        if edge.isHorizontal {
            let travel = max(visible.width - frame.width, 0)
            state.barOffset = travel > 0
                ? Double(((frame.minX - visible.minX) / travel).clamped(0, 1))
                : 0.5
        } else {
            let travel = max(visible.height - frame.height, 0)
            state.barOffset = travel > 0
                ? Double(((visible.maxY - frame.maxY) / travel).clamped(0, 1))
                : 0.5
        }

        state.barEdge = edge
        applyEdge()
    }
}

private extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lower), Swift.max(lower, upper))
    }
}
