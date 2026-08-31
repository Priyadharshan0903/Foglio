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
    private var observer: NSObjectProtocol?

    init(state: AppState, onPick: @escaping (Section) -> Void) {
        self.state = state

        panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 68, height: 300),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // the SwiftUI layer draws its own

        let host = NSHostingView(rootView: BarView(state: state, onPick: onPick))
        host.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = host

        // Size the panel to whatever the SwiftUI strip actually needs.
        let fitting = host.fittingSize
        panel.setContentSize(fitting)

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    /// Vertically centred, 22px in from the chosen screen edge (:913).
    func reposition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let inset: CGFloat = 22 - 10 // the SwiftUI view carries 10pt of shadow padding

        let x = state.barSide == .left
            ? visible.minX + inset
            : visible.maxX - size.width - inset
        let y = visible.midY - size.height / 2

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
