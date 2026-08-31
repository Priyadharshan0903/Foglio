import SwiftUI

/// The always-on-top edge strip (Day Log.dc.html:54-67).
struct BarView: View {
    @Bindable var state: AppState
    var onPick: (Section) -> Void

    @State private var hovered: Section?
    @State private var hoveredTimer = false
    @State private var pulsing = false

    private var theme: Theme { state.theme }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Section.barItems) { item in
                barButton(item)
            }

            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)

            timerButton
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 7)
        .background(theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
        .shadow(theme.shadowFloat)
        .padding(10) // room for the shadow inside the panel bounds
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
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? item : (hovered == item ? nil : hovered) }
        .help(item.label)
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
        .buttonStyle(.plain)
        .onHover { hoveredTimer = $0 }
        .help(state.timerRunning ? "Pause focus" : "Start focus")
        .onChange(of: state.timerRunning) { _, running in
            pulsing = running
        }
    }
}
