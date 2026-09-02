import SwiftUI
import AppKit

/// The dotted grab handle on the floating bar.
///
/// The whole strip is draggable, but nothing said so — a panel that looks like a
/// row of buttons reads as fixed. A grip plus a grab cursor is the conventional
/// way to signal "move me".
///
/// The grid runs *across* the bar: three dots wide by two tall on a vertical
/// bar, and the transpose on a horizontal one, so it always reads as a short
/// band rather than a column. It also takes the same 34pt cross-axis size as the
/// buttons below it, so everything shares one centre line.
struct GripHandle: View {
    /// True when the bar itself is horizontal (docked top).
    let horizontal: Bool
    let color: Color
    var isDragging: Bool = false

    private let dot: CGFloat = 2.5
    private let gap: CGFloat = 3.5

    var body: some View {
        Group {
            if horizontal {
                // Narrow and tall, sitting to the left of the buttons.
                HStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(spacing: gap) { dots }
                    }
                }
                .frame(height: 34)
            } else {
                // Wide and short, sitting above the buttons.
                VStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: gap) { dots }
                    }
                }
                .frame(width: 34)
            }
        }
        // No fixed cross-axis size: the grid is 8.5pt on its short side, and
        // pinning it to 12 clipped the dots and pushed them off centre.
        .padding(.vertical, horizontal ? 0 : 3)
        .padding(.horizontal, horizontal ? 3 : 0)
        .contentShape(Rectangle())
        .grabCursor(isDragging: isDragging)
        .help("Drag to move — it docks to the nearest edge")
    }

    private var dots: some View {
        ForEach(0..<3, id: \.self) { _ in
            Circle()
                .fill(color)
                .frame(width: dot, height: dot)
        }
    }
}

private struct GrabCursor: ViewModifier {
    let isDragging: Bool

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside {
                (isDragging ? NSCursor.closedHand : NSCursor.openHand).set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    func grabCursor(isDragging: Bool = false) -> some View {
        modifier(GrabCursor(isDragging: isDragging))
    }
}
