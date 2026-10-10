import AppKit
import SwiftUI

/// The detachable main window: header, 52pt icon rail, section content
/// (Day Log.dc.html:96-126).
struct MainWindowView: View {
    @Bindable var state: AppState
    let store: Store
    let calendar: CalendarSource

    @FocusState private var searchFocused: Bool
    /// Whether this view currently owns an `NSCursor` push — see `searchField`.
    @State private var cursorPushed = false

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
        .preferredColorScheme(state.theme.isDark ? .dark : .light)
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

            if [.notes, .tasks, .capture, .trash].contains(state.section) {
                searchField
            } else {
                Button {
                    state.section = .notes
                    state.searchFocusRequests += 1
                } label: {
                    Label("Search notes", systemImage: "magnifyingglass")
                        .font(Typo.sans(12)).foregroundStyle(theme.muted)
                }
                .buttonStyle(.flat)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: Self.headerHeight)
        .background(theme.surface)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            magnifier

            TextField(searchPlaceholder, text: $state.search)
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
        // Only the text field itself accepted a click, and it is 15pt tall
        // inside a 27pt pill — so the magnifier, the 6pt of padding above and
        // below, and the empty run to the right of the caret all did nothing.
        // Hit-testing the window confirmed it: clicks outside that middle band
        // landed on the hosting view and were dropped. The whole pill is the
        // control, so the whole pill focuses it.
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture { searchFocused = true }
        .onHover { inside in
            // Guarded: `push`/`pop` are a stack, and a double push (SwiftUI can
            // repeat an enter) would leave the I-beam stuck over the whole app.
            guard inside != cursorPushed else { return }
            cursorPushed = inside
            if inside { NSCursor.iBeam.push() } else { NSCursor.pop() }
        }
        .help("Search this section (⌘F)")
    }

    private var searchPlaceholder: String {
        switch state.section {
        case .notes: "Search notes…"
        case .tasks: "Search tasks…"
        case .capture: "Search today's activity…"
        case .trash: "Search deleted notes…"
        default: "Search notes…"
        }
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

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f.string(from: Date())
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(spacing: 6) {
            ForEach(Section.primaryItems) { item in navigationRow(item) }
            Divider().overlay(theme.line).padding(.vertical, 10)
            DisclosureGroup("More") {
                ForEach(Section.moreItems) { item in navigationRow(item) }
            }
            .disclosureGroupStyle(SidebarDisclosureStyle(theme: theme))
            .font(Typo.sans(11.5)).foregroundStyle(theme.muted)
            Spacer()
            ForEach(Section.utilityItems) { item in navigationRow(item) }
        }
        .padding(.horizontal, 10).padding(.vertical, 16)
        .frame(width: 140)
        .frame(maxHeight: .infinity)
        .background(theme.surface)
    }

    private func navigationRow(_ item: Section) -> some View {
        let active = state.section == item
        return Button {
            state.search = ""
            state.endNoteSelection()
            state.section = item
        } label: {
            HStack(spacing: 9) {
                IconView(icon: item.icon, size: 16)
                Text(item.label).font(Typo.sans(12, active ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? theme.accentDeep : theme.muted)
            .padding(.horizontal, 9).padding(.vertical, 10)
            .background(active ? theme.accentSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .hoverHighlight(theme, active: !active)
        }
        .buttonStyle(.flat)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(active ? .isSelected : [])
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
        case .trash:
            TrashView(state: state, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The arrow, text, and empty space form one keyboard-accessible control.
struct SidebarDisclosureStyle: DisclosureGroupStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: 9) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 9).padding(.vertical, 10)
                .contentShape(Rectangle())
                .hoverHighlight(theme)
            }
            .buttonStyle(.flat)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .help(configuration.isExpanded ? "Hide more sections" : "Show more sections")
            if configuration.isExpanded { configuration.content }
        }
    }
}
