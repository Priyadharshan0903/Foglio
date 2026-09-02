import SwiftUI

/// The detachable main window: header, 52pt icon rail, section content
/// (Day Log.dc.html:96-126).
struct MainWindowView: View {
    @Bindable var state: AppState
    let store: Store
    let calendar: CalendarSource

    @FocusState private var searchFocused: Bool

    /// A fixed height so `AppDelegate` can vertically center the native
    /// traffic lights against it deterministically, instead of guessing from
    /// text-driven intrinsic sizing.
    static let headerHeight: CGFloat = 38

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
        // The window uses fullSizeContentView so the header *is* the titlebar,
        // with the traffic lights sitting in it — as the design draws it
        // (:98). Without this SwiftUI keeps the titlebar safe area and pushes
        // the header down below an empty strip.
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.theme, theme)
        .preferredColorScheme(state.themeMode == .dark ? .dark : .light)
        .onChange(of: state.searchFocusRequests) { _, _ in searchFocused = true }
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
        .frame(height: Self.headerHeight)
        .background(theme.surface)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            magnifier

            TextField("Search notes, tasks, log…", text: $state.search)
                .textFieldStyle(.plain)
                .font(Typo.sans(12.5))
                .foregroundStyle(theme.text)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }

            // Without this a filter can be left applied with no obvious way
            // back — the field looks inert once focus moves away.
            if !state.search.isEmpty {
                Button {
                    state.search = ""
                    searchFocused = false
                } label: {
                    Text("×")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.muted)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.flat)
                .help("Clear search (⎋)")
            }
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
        .buttonStyle(.flat)
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
                        .hoverHighlight(theme, active: !isActive)
                }
                .buttonStyle(.flat)
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
        switch state.section {
        case .notes:
            NotesView(state: state, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tasks:
            TasksView(state: state, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .capture:
            CaptureView(state: state, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .settings:
            SettingsView(state: state, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .roadmap:
            RoadmapView(state: state, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .week:
            WeekView(state: state, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .calendar:
            CalendarView(state: state, store: store, calendar: calendar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
