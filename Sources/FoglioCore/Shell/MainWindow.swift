import AppKit

/// The detachable main window.
///
/// `cancelOperation` is the tail of the responder chain for Escape, so it only
/// fires when nothing nearer handled it — a block being edited consumes Escape
/// to stop editing, and only an idle window closes. That's exactly the design's
/// "⎋ — send the window away, keep the bar" (:1229): the app stays alive
/// because `applicationShouldTerminateAfterLastWindowClosed` is false.
final class MainWindow: NSWindow {
    /// Return true if the Escape was consumed (e.g. it cleared a search) and
    /// the window should stay open.
    var onCancel: (() -> Bool)?

    override func cancelOperation(_ sender: Any?) {
        if onCancel?() == true { return }
        close()
    }
}
