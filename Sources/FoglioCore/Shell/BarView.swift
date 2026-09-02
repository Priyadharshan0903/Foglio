import SwiftUI
import AppKit

/// The always-on-top edge strip (Day Log.dc.html:54-67).
///
/// Runs vertically when docked left or right and horizontally on top, and can be
/// dragged anywhere — it docks to whichever edge it's dropped nearest.
struct BarView: View {
    struct DragHandlers {
        let onChanged: (CGSize) -> Void
        let onEnded: () -> Void
    }

    @Bindable var state: AppState
    var onPick: (Section) -> Void
    var drag: DragHandlers?
    /// Text for the calendar badge, e.g. "8m" — nil when nothing is coming up.
    var meetingBadge: String?

    @State private var hovered: Section?
    @State private var hoveredTimer = false
    @State private var pulsing = false
    @State private var isDragging = false

    private var theme: Theme { state.theme }
    private var horizontal: Bool { state.barEdge.isHorizontal }

    var body: some View {
        let layout = horizontal
            ? AnyLayout(HStackLayout(spacing: 6))
            : AnyLayout(VStackLayout(spacing: 6))

        layout {
            GripHandle(horizontal: horizontal, color: theme.muted.opacity(0.55), isDragging: isDragging)
                .padding(horizontal ? .trailing : .bottom, 2)

            ForEach(Section.barItems) { item in
                barButton(item)
            }
            divider
            timerButton
        }
        .padding(horizontal ? .horizontal : .vertical, 8)
        .padding(horizontal ? .vertical : .horizontal, 7)
        .background(theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
        // No scale-up while dragging: the panel is sized exactly to this view,
        // so scaling it clipped at the panel bounds and added to the flicker.
        // The closed-hand cursor carries the same feedback for free.
        .gesture(dragGesture)
    }

    /// `minimumDistance` is what lets a plain click still reach the buttons
    /// underneath — only actual movement starts a drag.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                isDragging = true
                drag?.onChanged(value.translation)
            }
            .onEnded { _ in
                isDragging = false
                NSCursor.openHand.set()
                drag?.onEnded()
            }
    }

    @ViewBuilder
    private var divider: some View {
        if horizontal {
            Rectangle()
                .fill(theme.line)
                .frame(width: 1)
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
        } else {
            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
    }

    private func barButton(_ item: Section) -> some View {
        let isActive = state.section == item
        return Button {
            onPick(item)
        } label: {
            IconView(icon: item.icon)
                .foregroundStyle(isActive ? theme.accentDeep : theme.muted)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? theme.accentSoft
                              : (hovered == item ? theme.accentSoft : .clear))
                )
                .overlay(alignment: .topTrailing) {
                    if item == .calendar, let badge = meetingBadge {
                        Text(badge)
                            .font(Typo.mono(9.5, .medium))
                            .foregroundStyle(theme.raised)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 17, minHeight: 15)
                            .background(Capsule().fill(theme.clay))
                            .overlay(Capsule().strokeBorder(theme.raised, lineWidth: 2))
                            .offset(x: 5, y: -4)
                            .fixedSize()
                    }
                }
        }
        .buttonStyle(.flat)
        .onHover { hovered = $0 ? item : (hovered == item ? nil : hovered) }
        .help(badgeHelp(for: item))
    }

    private func badgeHelp(for item: Section) -> String {
        guard item == .calendar, let badge = meetingBadge else { return item.label }
        return "Next meeting \(badge == "now" ? "now" : "in \(badge)")"
    }

    private var timerButton: some View {
        Button {
            state.toggleTimer()
        } label: {
            IconView(icon: .timer)
                .foregroundStyle(state.timerRunning ? theme.accentDeep : theme.muted)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hoveredTimer ? theme.accentSoft : .clear)
                )
                // `dl-pulse 2s ease-in-out infinite` while running (:64)
                .opacity(state.timerRunning && pulsing ? 0.35 : 1)
                .animation(
                    state.timerRunning
                        ? .easeInOut(duration: 1).repeatForever(autoreverses: true)
                        : .default,
                    value: pulsing
                )
        }
        .buttonStyle(.flat)
        .onHover { hoveredTimer = $0 }
        .help(state.timerRunning ? "Pause focus" : "Start focus")
        .onChange(of: state.timerRunning) { _, running in
            pulsing = running
        }
    }
}
