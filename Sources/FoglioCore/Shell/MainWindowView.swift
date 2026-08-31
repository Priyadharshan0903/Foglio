import SwiftUI

/// The detachable main window: header, 52pt icon rail, section content
/// (Day Log.dc.html:96-126).
struct MainWindowView: View {
    @Bindable var state: AppState
    let store: Store

    private var theme: Theme { state.theme }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.line)
            HStack(spacing: 0) {
                rail
                Divider().overlay(theme.line)
                content
            }
        }
        .background(theme.bg)
        .environment(\.theme, theme)
        .preferredColorScheme(state.themeMode == .dark ? .dark : .light)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            // Space for the native traffic lights, which sit over the content
            // because the window uses a transparent full-size titlebar.
            Color.clear.frame(width: 62, height: 1)

            Text(state.section.label)
                .font(Typo.sans(12.5, .medium))
                .foregroundStyle(theme.text)

            Text(dateLabel)
                .font(Typo.sans(12))
                .foregroundStyle(theme.muted)

            Spacer(minLength: 12)

            searchField

            if state.timerRunning {
                Text(state.mmss)
                    .font(Typo.mono(13.5))
                    .foregroundStyle(theme.accentDeep)
                    .monospacedDigit()
            }

            focusButton
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(theme.surface)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            magnifier

            TextField("Search notes, tasks, log…", text: $state.search)
                .textFieldStyle(.plain)
                .font(Typo.sans(12.5))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 232)
        .background(theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }

    private var magnifier: some View {
        // M11 4a7 7 0 100 14 7 7 0 000-14 M16.2 16.2L20 20  (:108)
        Path { p in
            p.addEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 14))
            p.move(to: CGPoint(x: 16.2, y: 16.2))
            p.addLine(to: CGPoint(x: 20, y: 20))
        }
        .applying(CGAffineTransform(scaleX: 13.0 / 24, y: 13.0 / 24))
        .stroke(theme.muted, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        .frame(width: 13, height: 13)
    }

    private var focusButton: some View {
        Button {
            state.toggleTimer()
        } label: {
            Text(state.timerRunning ? "PAUSE" : "FOCUS")
                .font(Typo.sans(11, .semibold))
                .kerning(0.44)
                .foregroundStyle(state.timerRunning ? theme.text : theme.onAccent)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(state.timerRunning ? Color.clear : theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f.string(from: Date())
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(spacing: 6) {
            ForEach(Section.railItems) { item in
                let isActive = state.section == item
                Button {
                    state.section = item
                } label: {
                    IconView(icon: item.icon)
                        .foregroundStyle(isActive ? theme.accentDeep : theme.muted)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isActive ? theme.accentSoft : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(item.label)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(theme.surface)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.section.label)
                .font(Typo.sans(19, .semibold))
                .foregroundStyle(theme.text)
            Text("Not built yet — \(store.notes.count) notes, \(store.tasks.count) tasks, \(store.todaysLog.count) log entries loaded from \(store.root.path).")
                .font(Typo.sans(12.5))
                .foregroundStyle(theme.muted)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg)
    }
}
