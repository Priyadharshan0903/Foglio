import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A week grid, in the shape people already know from Google Calendar.
///
/// The design showed a single day beside a fixed inspector column (:377-458). A
/// day is too little to plan against, so this shows the whole week and moves the
/// details into a sheet — with seven columns there's no room for a permanent
/// 288pt inspector.
struct CalendarView: View {
    @Bindable var state: AppState
    let store: Store
    let calendar: CalendarSource

    /// Anchor for the visible week.
    @State private var anchor = Date()
    @State private var selected: DayEvent?
    @State private var showSourcePicker = false

    private let hourHeight: CGFloat = 44
    private let gutter: CGFloat = 52

    private var theme: Theme { state.theme }

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // Monday, as work weeks are read
        return c
    }

    private var week: DateInterval { CalendarSource.week(containing: anchor) }

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
    }

    /// The full day, always — a fixed 9am–6pm window hid anything scheduled
    /// outside it with no way to scroll there. `initialScrollHour` still opens
    /// on the part of the day that matters instead of midnight.
    private let hours: [Int] = Array(0...23)

    /// Where the grid opens: two hours before now, so "now" isn't pinned to
    /// the very top edge — but never below midnight.
    private var initialScrollHour: Int {
        max(0, cal.component(.hour, from: Date()) - 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(theme.line)

            if calendar.needsSetup || showSourcePicker {
                ScrollView { setupPanel.padding(.horizontal, 32).padding(.vertical, 24) }
            } else {
                grid
            }
        }
        .background(theme.bg)
        .task(id: anchor) { await calendar.refresh(range: week) }
        .sheet(item: $selected) { event in
            EventDetailSheet(
                state: state,
                event: event,
                onTakeNotes: { takeNotes(on: event); selected = nil },
                onAddFollowUp: { addFollowUp(for: event); selected = nil },
                onClose: { selected = nil }
            )
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(weekLabel)
                .font(Typo.sans(15, .semibold))
                .kerning(-0.3)
                .foregroundStyle(theme.text)

            HStack(spacing: 2) {
                stepButton("‹", help: "Previous week") { shiftWeek(-1) }
                stepButton("›", help: "Next week") { shiftWeek(1) }
            }

            Button { anchor = Date() } label: {
                Text("Today")
                    .font(Typo.sans(11.5, .medium))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.flat)

            Spacer()

            if calendar.isLoading {
                Text("Loading…").font(Typo.sans(11.5)).foregroundStyle(theme.muted)
            } else if !calendar.events.isEmpty {
                Text("\(calendar.events.count) events")
                    .font(Typo.sans(11.5)).foregroundStyle(theme.muted)
            }

            if calendar.backend == .file, let age = calendar.snapshotAge, !calendar.needsSetup {
                snapshotChip(age: age)
            }

            Button { showSourcePicker.toggle() } label: {
                Text(showSourcePicker ? "Done" : "Source")
                    .font(Typo.sans(11.5, .medium))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .hoverHighlight(theme, cornerRadius: 5)
            }
            .buttonStyle(.flat)

            Button { Task { await calendar.refresh(range: week) } } label: {
                Text("Refresh")
                    .font(Typo.sans(11.5, .medium))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .hoverHighlight(theme, cornerRadius: 5)
            }
            .buttonStyle(.flat)
        }
        .padding(.horizontal, 24).padding(.vertical, 9)
    }

    private func stepButton(_ glyph: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 15))
                .foregroundStyle(theme.muted)
                .frame(width: 24, height: 24)
                .hoverHighlight(theme, cornerRadius: 5)
        }
        .buttonStyle(.flat)
        .help(help)
    }

    private func shiftWeek(_ delta: Int) {
        if let next = cal.date(byAdding: .weekOfYear, value: delta, to: anchor) { anchor = next }
    }

    /// "1–7 Sep 2026" within a month, "29 Sep – 5 Oct 2026" across one.
    private var weekLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        let last = days.last ?? week.start

        if cal.isDate(week.start, equalTo: last, toGranularity: .month) {
            f.dateFormat = "d"
            let start = f.string(from: week.start)
            f.dateFormat = "d MMM yyyy"
            return "\(start)–\(f.string(from: last))"
        }
        f.dateFormat = "d MMM"
        let start = f.string(from: week.start)
        f.dateFormat = "d MMM yyyy"
        return "\(start) – \(f.string(from: last))"
    }

    private func snapshotChip(age: String) -> some View {
        let stale = calendar.snapshotIsStale
        return HStack(spacing: 6) {
            Circle().fill(stale ? theme.clay : theme.ok).frame(width: 5, height: 5)
            Text("exported \(age)")
                .font(Typo.sans(11))
                .foregroundStyle(stale ? theme.text : theme.muted)
            if stale {
                Button { NSWorkspace.shared.open(CalendarSource.googleExportURL) } label: {
                    Text("Re-export")
                        .font(Typo.sans(11, .semibold))
                        .foregroundStyle(theme.accentDeep)
                }
                .buttonStyle(.flat)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(stale ? theme.accentSoft : theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .help(stale ? "This snapshot predates anything scheduled since" : "When this export was made")
    }

    // MARK: - Week grid

    private var grid: some View {
        VStack(spacing: 0) {
            dayHeaders
            Divider().overlay(theme.line)
            // GeometryReader supplies the viewport height so short weeks can be
            // pinned to the top with `minHeight` — `maxHeight` would instead
            // force *every* week to exactly that height and break scrolling
            // once a week's hour range grows past it.
            GeometryReader { proxy in
                ScrollViewReader { scroller in
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            hourGutter
                            ForEach(days, id: \.self) { day in
                                dayColumn(day)
                                if day != days.last { Divider().overlay(theme.lineSoft) }
                            }
                        }
                        .frame(minHeight: proxy.size.height, alignment: .top)
                        .padding(.bottom, 24)
                    }
                    .task(id: anchor) { scroller.scrollTo(initialScrollHour, anchor: .top) }
                }
            }
        }
    }

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            // Spacer, not Color: `Color` is infinitely flexible in both axes, so
            // giving it only a width let it stretch this row to fill the view
            // and stranded the day names in the middle of it.
            Spacer().frame(width: gutter)

            ForEach(days, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                VStack(spacing: 2) {
                    Text(weekdayName(day).uppercased())
                        .font(Typo.sans(9.5))
                        .kerning(1.1)
                        .foregroundStyle(isToday ? theme.accentDeep : theme.muted)
                    Text("\(cal.component(.day, from: day))")
                        .font(Typo.sans(12.5, isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? theme.onAccent : theme.text)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isToday ? theme.accent : .clear))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.surface)
    }

    private func weekdayName(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE"
        return f.string(from: day)
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(Typo.mono(10))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                    .frame(height: hourHeight, alignment: .top)
                    .offset(y: -5)
                    .id(hour)
            }
        }
        .frame(width: gutter)
    }

    private func dayColumn(_ day: Date) -> some View {
        let events = calendar.events(on: day)

        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { _ in
                    VStack(spacing: 0) {
                        Rectangle().fill(theme.lineSoft).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: hourHeight)
                }
            }

            if cal.isDateInToday(day) { nowLine }

            ForEach(events) { event in
                eventBlock(event)
                    .frame(height: height(for: event))
                    .offset(y: offset(for: event))
                    .padding(.horizontal, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: CGFloat(hours.count) * hourHeight)
        .background(cal.isDateInToday(day) ? theme.accentSoft.opacity(0.22) : .clear)
    }

    /// A hairline at the current time — the thing that makes a calendar feel live.
    @ViewBuilder
    private var nowLine: some View {
        let minutes = CGFloat(cal.component(.hour, from: Date()) * 60
            + cal.component(.minute, from: Date()))
        let y = (minutes - CGFloat((hours.first ?? 9) * 60)) / 60 * hourHeight

        if y >= 0, y <= CGFloat(hours.count) * hourHeight {
            Rectangle()
                .fill(theme.clay)
                .frame(height: 1.5)
                .offset(y: y)
        }
    }

    private func offset(for event: DayEvent) -> CGFloat {
        let minutes = CGFloat(cal.component(.hour, from: event.start) * 60
            + cal.component(.minute, from: event.start))
        return (minutes - CGFloat((hours.first ?? 9) * 60)) / 60 * hourHeight
    }

    private func height(for event: DayEvent) -> CGFloat {
        let minutes = CGFloat(event.end.timeIntervalSince(event.start) / 60)
        return max(22, minutes / 60 * hourHeight - 2)
    }

    private func eventBlock(_ event: DayEvent) -> some View {
        Button { selected = event } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(Typo.sans(11, .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if height(for: event) > 34 {
                    Text(Clock.hhmm(event.start))
                        .font(Typo.mono(9.5))
                        .opacity(0.7)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(theme.accentSoft)
            .overlay(alignment: .leading) {
                Rectangle().fill(theme.accentDeep).frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .opacity(event.isPast ? 0.55 : 1)
        }
        .buttonStyle(.flat)
        .help("\(event.title) — \(Clock.hhmm(event.start))–\(Clock.hhmm(event.end))")
    }

    // MARK: - Source setup

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Where should meetings come from?")
                    .font(Typo.sans(14, .medium))
                    .foregroundStyle(theme.text)
                Text("Google Workspace admins can block third-party apps from signing in, so Foglio reads your calendar without an account connection.")
                    .font(Typo.sans(12.5))
                    .foregroundStyle(theme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 3) {
                ForEach(CalendarBackend.allCases) { option in
                    let isSelected = calendar.backend == option
                    Button { calendar.backend = option } label: {
                        Text(option.label)
                            .font(Typo.sans(11.5, .medium))
                            .foregroundStyle(isSelected ? theme.onAccent : theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isSelected ? theme.accent : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.flat)
                }
            }
            .padding(3)
            .background(theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 1)
            )

            Text(calendar.backend.hint)
                .font(Typo.sans(11.5))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            switch calendar.backend {
            case .eventKit: eventKitControls
            case .subscription: subscriptionControls
            case .file: fileControls
            }

            if let status = calendar.status {
                Text(status)
                    .font(Typo.sans(11.5))
                    .foregroundStyle(theme.clay)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var eventKitControls: some View {
        switch calendar.access {
        case .granted:
            Text("Connected to the Calendar app.")
                .font(Typo.sans(11.5)).foregroundStyle(theme.muted)
        case .denied, .restricted:
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            } label: { pillLabel("Open System Settings", filled: false) }
            .buttonStyle(.flat)
        case .unknown:
            Button { Task { await calendar.requestAccess() } } label: {
                pillLabel("Grant Calendar access", filled: true)
            }
            .buttonStyle(.flat)
        }
    }

    private var subscriptionControls: some View {
        HStack(spacing: 8) {
            TextField("https://calendar.google.com/calendar/ical/…/basic.ics", text: subscriptionBinding)
                .textFieldStyle(.plain)
                .font(Typo.mono(11.5))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.line, lineWidth: 1)
                )
                .onSubmit { Task { await calendar.refresh(range: week) } }

            Button { Task { await calendar.refresh(range: week) } } label: {
                pillLabel("Fetch", filled: true)
            }
            .buttonStyle(.flat)
        }
    }

    private var subscriptionBinding: Binding<String> {
        Binding(get: { calendar.subscriptionURL }, set: { calendar.subscriptionURL = $0 })
    }

    private var fileControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { chooseImport() } label: {
                    pillLabel(calendar.importPath == nil ? "Choose export…" : "Change…",
                              filled: calendar.importPath == nil)
                }
                .buttonStyle(.flat)

                if calendar.importPath != nil {
                    Button { Task { await calendar.refresh(range: week) } } label: {
                        pillLabel("Reload", filled: true)
                    }
                    .buttonStyle(.flat)
                }
            }

            if let description = calendar.importDescription {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reading \(description)")
                        .font(Typo.mono(11))
                        .foregroundStyle(theme.muted)
                    Text("Watching that location — a new export is picked up automatically.")
                        .font(Typo.sans(11))
                        .foregroundStyle(theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        // A folder is the better choice: Google names each export differently
        // ("… (1).zip"), so watching the folder survives re-exporting.
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data, .zip, .folder]
        panel.prompt = "Use this"
        panel.message = "Choose the exported .zip or .ics — or pick your Downloads folder to pick up each new export automatically."
        if panel.runModal() == .OK, let url = panel.url {
            calendar.chooseImport(at: url)
        }
    }

    private func pillLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(Typo.sans(12, filled ? .semibold : .medium))
            .foregroundStyle(filled ? theme.onAccent : theme.text)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(filled ? theme.accent : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(filled ? .clear : theme.line, lineWidth: 1)
            )
    }

    // MARK: - Actions

    /// `selNoteAction` (:988) — a note titled after the meeting, ready to type into.
    private func takeNotes(on event: DayEvent) {
        let note = Note(
            title: event.title,
            body: Markdown.serialize([
                .h2("\(Clock.hhmm(event.start)) · \(event.location)"),
                .paragraph(""),
            ]),
            folder: .scratch
        )
        store.upsert(note)
        state.section = .notes
        state.activeNoteId = note.id
        state.activeBlock = 1
    }

    /// `selTaskAction` (:937).
    private func addFollowUp(for event: DayEvent) {
        store.addTask(TaskItem(
            label: "Follow up: \(event.title)",
            lane: .delegate,
            meta: "From calendar"
        ))
        state.section = .tasks
    }
}
