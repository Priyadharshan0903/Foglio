import AppKit
import SwiftUI
@testable import FoglioCore

@MainActor
func taskDragScrollTests() {
    Check.suite("Task dragging — edge scroll speed and limits") {
        let viewport = CGRect(x: 8, y: 48, width: 284, height: 300)
        func speed(_ y: CGFloat, x: CGFloat = 100) -> CGFloat {
            TaskDragScroll.velocity(at: CGPoint(x: x, y: y), in: viewport)
        }
        Check.equal(speed(180), 0, "the lane's middle stays still for accurate placement")
        Check.expect(speed(58) < 0, "the upper edge scrolls toward earlier cards")
        Check.expect(speed(338) > 0, "the lower edge scrolls toward later cards")
        Check.expect(speed(346) > speed(320), "scrolling accelerates closer to the edge")
        Check.equal(speed(48), -900, "the upper edge has a bounded maximum speed")
        Check.equal(speed(348), 900, "the lower edge has a bounded maximum speed")
        for point in [CGPoint(x: 7, y: 340), CGPoint(x: 293, y: 340),
                      CGPoint(x: 100, y: 47), CGPoint(x: 100, y: 349)] {
            Check.equal(TaskDragScroll.velocity(at: point, in: viewport), 0,
                        "the header, neighboring lanes, and outside the viewport cannot scroll this lane")
        }
        Check.equal(TaskDragScroll.velocity(at: .zero, in: .zero), 0, "an unlaid-out lane cannot scroll")
        Check.equal(TaskDragScroll.velocity(at: CGPoint(x: 20, y: 30), in: CGRect(x: 0, y: 0, width: 40, height: 60)), 0,
                    "short lanes still have a stationary middle region")
        let document = CGRect(x: 0, y: 10, width: 280, height: 2000)
        func offset(_ current: CGFloat, _ speed: CGFloat, _ elapsed: TimeInterval = 1.0 / 60) -> CGFloat {
            TaskDragScroll.offset(current: current, velocity: speed, elapsed: elapsed,
                                  document: document, viewportHeight: 300)
        }
        Check.equal(offset(10, -900), 10, "scrolling stops at the document's first edge")
        Check.equal(offset(1705, 900), 1710, "scrolling stops at the document's final edge")
        Check.equal(offset(100, 900, 10), 145, "an event-loop pause cannot produce a large jump")
        Check.equal(offset(100, 900, -1), 100, "a reversed clock interval cannot scroll backwards")
        Check.equal(TaskDragScroll.offset(current: 0, velocity: 900, elapsed: 1,
                                         document: CGRect(x: 0, y: 0, width: 280, height: 120), viewportHeight: 300), 0,
                    "an empty or short lane has no scrollable range")
    }

    Check.suite("Task dragging — horizontal board edges") {
        let viewport = CGRect(x: 0, y: 0, width: 500, height: 320)
        Check.expect(TaskDragScroll.velocity(at: CGPoint(x: 499, y: 160), in: viewport, axis: .horizontal) > 0,
                     "the board's right edge scrolls toward hidden lanes")
        Check.expect(TaskDragScroll.velocity(at: CGPoint(x: 1, y: 160), in: viewport, axis: .horizontal) < 0,
                     "the board's left edge scrolls toward earlier lanes")
        Check.equal(TaskDragScroll.velocity(at: CGPoint(x: 250, y: 1), in: viewport, axis: .horizontal), 0,
                    "vertical lane edges do not accidentally move the whole board")
        let scroll = NSScrollView(frame: viewport)
        let document = TaskScrollTestDocument(frame: CGRect(x: 0, y: 0, width: 5000, height: 500))
        scroll.documentView = document
        let driver = TaskDragAutoScrollView()
        driver.axis = .horizontal
        driver.isDragActive = true
        let clip = scroll.contentView
        clip.scroll(to: CGPoint(x: 0, y: 20))
        for _ in 0..<400 {
            driver.advance(scroll, pointer: CGPoint(x: clip.bounds.maxX - 1, y: clip.bounds.midY), elapsed: 1.0 / 60)
        }
        Check.equal(clip.bounds.maxX, document.bounds.maxX, "continuous horizontal scrolling reaches the last lane")
        Check.equal(clip.bounds.minY, 20, "board scrolling preserves vertical position")
        for _ in 0..<400 {
            driver.advance(scroll, pointer: CGPoint(x: clip.bounds.minX + 1, y: clip.bounds.midY), elapsed: 1.0 / 60)
        }
        Check.equal(clip.bounds.minX, 0, "horizontal scrolling can return to the first lane")
        driver.isDragActive = false
        Check.expect(!driver.advance(scroll, pointer: CGPoint(x: clip.bounds.maxX - 1, y: clip.bounds.midY), elapsed: 1.0 / 60),
                     "ending a drag stops horizontal scrolling too")
    }

    Check.suite("Task dragging — native continuous lane scrolling") {
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 320))
        let document = TaskScrollTestDocument(frame: CGRect(x: 0, y: 0, width: 500, height: 5000))
        scroll.documentView = document
        let driver = TaskDragAutoScrollView()
        driver.isDragActive = true
        let clip = scroll.contentView
        clip.scroll(to: CGPoint(x: 20, y: 0))
        for _ in 0..<400 {
            let pointer = CGPoint(x: clip.bounds.midX, y: clip.bounds.maxY - 1)
            driver.advance(scroll, pointer: pointer, elapsed: 1.0 / 60)
        }
        Check.equal(clip.bounds.maxY, document.bounds.maxY, "holding a card near the bottom reaches the final cards")
        Check.equal(clip.bounds.minX, 20, "vertical dragging preserves horizontal position")
        let bottom = clip.bounds.origin
        Check.expect(!driver.advance(scroll, pointer: CGPoint(x: clip.bounds.midX, y: clip.bounds.maxY - 1), elapsed: 1.0 / 60),
                     "holding at the bottom stops without overscroll")
        Check.expect(!driver.advance(scroll, pointer: CGPoint(x: clip.bounds.midX, y: clip.bounds.midY), elapsed: 1.0 / 60),
                     "moving to the middle pauses native scrolling")
        Check.equal(clip.bounds.origin, bottom, "pausing keeps the current position")
        for _ in 0..<400 {
            let pointer = CGPoint(x: clip.bounds.midX, y: clip.bounds.minY + 1)
            driver.advance(scroll, pointer: pointer, elapsed: 1.0 / 60)
        }
        Check.equal(clip.bounds.minY, 0, "holding a card near the top reaches the first cards")
        driver.isDragActive = false
        Check.expect(!driver.advance(scroll, pointer: CGPoint(x: clip.bounds.midX, y: clip.bounds.maxY - 1), elapsed: 1.0 / 60),
                     "dropping or cancelling stops scrolling")
        Check.equal(clip.bounds.minY, 0, "a finished drag cannot move the viewport")
        Check.expect(driver.hitTest(.zero) == nil, "the scroll bridge cannot intercept a card's click or drop")
    }

    Check.suite("Task dragging — nested board scroll integration") {
        let host = NSHostingView(rootView: ScrollView(.horizontal) {
            HStack {
                ForEach(0..<2) { _ in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(0..<50) { Text("Fictional task \($0)").frame(maxWidth: .infinity).frame(height: 60) }
                        }
                            .background(TaskDragAutoScroll(isDragging: false)
                                .allowsHitTesting(false).accessibilityHidden(true))
                    }.frame(width: 300, height: 320)
                }
            }
            .background(TaskDragAutoScroll(isDragging: false, axis: .horizontal)
                .allowsHitTesting(false).accessibilityHidden(true))
        })
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        func bridges(_ root: NSView) -> [TaskDragAutoScrollView] {
            (root as? TaskDragAutoScrollView).map { [$0] } ?? root.subviews.flatMap { bridges($0) }
        }
        let drivers = bridges(host)
        let lanes = drivers.filter { $0.axis == .vertical }
        let board = drivers.first { $0.axis == .horizontal }
        Check.equal(lanes.count, 2, "each lane installs its own scroll driver")
        Check.expect(lanes.count == 2 && lanes.allSatisfy {
            guard let scroll = $0.enclosingScrollView, let document = scroll.documentView else { return false }
            return document.bounds.height > scroll.contentView.bounds.height
        }, "drivers resolve the vertical lane rather than the surrounding horizontal board")
        if lanes.count == 2 {
            Check.expect(lanes[0].enclosingScrollView !== lanes[1].enclosingScrollView, "scrolling one lane cannot move its neighbor")
            if let lane = lanes[0].enclosingScrollView, let neighbor = lanes[1].enclosingScrollView {
                let before = lane.contentView.bounds.origin
                let neighborBefore = neighbor.contentView.bounds.origin
                lanes[0].isDragActive = true
                let pointer = CGPoint(x: lane.contentView.bounds.midX, y: lane.contentView.bounds.maxY - 1)
                Check.expect(lanes[0].advance(lane, pointer: pointer, elapsed: 1.0 / 60),
                             "the bridge advances a real SwiftUI lane's native viewport")
                Check.expect(lane.contentView.bounds.minY > before.y, "a SwiftUI lane exposes later cards")
                Check.equal(neighbor.contentView.bounds.origin, neighborBefore, "the adjacent SwiftUI lane stays still")
                lanes[0].isDragActive = false
            }
        }
        Check.expect(board?.enclosingScrollView != nil && board?.enclosingScrollView !== lanes.first?.enclosingScrollView,
                     "the board driver resolves the surrounding horizontal scroll view")
        if let board, let scroll = board.enclosingScrollView {
            board.isDragActive = true
            let pointer = CGPoint(x: scroll.contentView.bounds.maxX - 1, y: scroll.contentView.bounds.midY)
            Check.expect(board.advance(scroll, pointer: pointer, elapsed: 1.0 / 60),
                         "the real SwiftUI board scrolls to reveal another lane")
            board.isDragActive = false
        }
    }
}

private final class TaskScrollTestDocument: NSView {
    override var isFlipped: Bool { true }
}
