import AppKit
import SwiftUI

/// Points per second toward the nearest scrolling edge. A quiet middle region
/// lets users position a card without moving the board beneath it.
enum TaskDragScroll {
    enum Axis { case vertical, horizontal }

    static func velocity(at point: CGPoint, in viewport: CGRect, axis: Axis = .vertical) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0,
              point.x >= viewport.minX, point.x <= viewport.maxX,
              point.y >= viewport.minY, point.y <= viewport.maxY else { return 0 }
        let length = axis == .vertical ? viewport.height : viewport.width
        let coordinate = axis == .vertical ? point.y : point.x
        let start = axis == .vertical ? viewport.minY : viewport.minX
        let end = axis == .vertical ? viewport.maxY : viewport.maxX
        let edge = min(64, length / 3)
        let leading = (edge - (coordinate - start)) / edge
        let trailing = (edge - (end - coordinate)) / edge
        if leading > 0 { return -900 * leading * leading }
        if trailing > 0 { return 900 * trailing * trailing }
        return 0
    }

    static func offset(current: CGFloat, velocity: CGFloat, elapsed: TimeInterval,
                       document: CGRect, viewportHeight: CGFloat) -> CGFloat {
        let end = max(document.minY, document.maxY - viewportHeight)
        // Limit pauses in the event loop so the next frame cannot jump a lane.
        return min(max(current + velocity * CGFloat(min(max(elapsed, 0), 1.0 / 20)), document.minY), end)
    }
}

/// Placed inside scroll content to find its own native scroll view: a vertical
/// lane or the horizontal board. It never takes mouse/drop events.
struct TaskDragAutoScroll: NSViewRepresentable {
    let isDragging: Bool
    var axis: TaskDragScroll.Axis = .vertical

    func makeNSView(context: Context) -> TaskDragAutoScrollView {
        let view = TaskDragAutoScrollView()
        view.axis = axis
        view.isDragActive = isDragging
        return view
    }
    func updateNSView(_ view: TaskDragAutoScrollView, context: Context) {
        view.axis = axis
        view.isDragActive = isDragging
    }
    static func dismantleNSView(_ view: TaskDragAutoScrollView, coordinator: ()) {
        view.isDragActive = false
    }
}

final class TaskDragAutoScrollView: NSView {
    var axis: TaskDragScroll.Axis = .vertical
    var isDragActive = false { didSet { updateTimer() } }
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }

    private func updateTimer() {
        guard isDragActive, window != nil else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        // A native drag runs in AppKit's tracking loop; a default-mode timer
        // alone would stop precisely when the pointer is held at an edge.
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastTick
        lastTick = now
        guard isDragActive, NSEvent.pressedMouseButtons & 1 != 0,
              let scroll = enclosingScrollView, let window = scroll.window else { return }
        let clip = scroll.contentView
        let pointer = clip.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        // The outer board may clip part of a lane when scrolled sideways.
        guard clip.visibleRect.contains(pointer) else { return }
        advance(scroll, pointer: pointer, elapsed: elapsed)
    }

    /// Uses clip coordinates, so flipped and unflipped documents both scroll
    /// toward the pointer. Reading the cursor each tick also supports a still hand.
    @discardableResult
    func advance(_ scroll: NSScrollView, pointer: CGPoint, elapsed: TimeInterval) -> Bool {
        guard isDragActive, let document = scroll.documentView else { return false }
        let clip = scroll.contentView
        let viewport = clip.bounds
        let velocity = TaskDragScroll.velocity(at: pointer, in: viewport, axis: axis)
        guard velocity != 0 else { return false }
        let vertical = axis == .vertical
        let extent = vertical ? document.bounds : CGRect(x: 0, y: document.bounds.minX,
                                                        width: document.bounds.height, height: document.bounds.width)
        let current = vertical ? viewport.minY : viewport.minX
        let next = TaskDragScroll.offset(current: current, velocity: velocity, elapsed: elapsed,
                                         document: extent, viewportHeight: vertical ? viewport.height : viewport.width)
        guard abs(next - current) > 0.01 else { return false }
        let proposed = CGRect(origin: CGPoint(x: vertical ? viewport.minX : next,
                                              y: vertical ? next : viewport.minY), size: viewport.size)
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scroll.reflectScrolledClipView(clip)
        return true
    }
}
