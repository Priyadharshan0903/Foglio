import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Today's timeline with an event detail panel (Day Log.dc.html:377-458).
struct CalendarView: View {
    @Bindable var state: AppState
    let store: Store
    let calendar: CalendarSource

    /// 09:00–18:00 at 58pt per hour, as in the design (:951).
    private let firstHour = 9
    private let lastHour = 18
    private let hourHeight: CGFloat = 58

    private var theme: Theme { state.theme }

    @State private var showSourcePicker = false

    private var selected: DayEvent? {
        calendar.events.first { $0.id == state.selectedEventId }
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                timelineColumn
                sidebar.frame(width: 288)
            }
            .padding(.horizontal, 32)
            .padding(.top, 26).padding(.bottom, 40)
        }
        .background(theme.bg)
        .task { await calendar.refresh() }
    }

    // MARK: - Timeline

    private var timelineColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Today")
                    .font(Typo.sans(19, .semibold))
                    .kerning(-0.3)
                    .foregroundStyle(theme.text)
                Text(dateLabel)
                    .font(Typo.sans(12.5))
                    .foregroundStyle(theme.muted)
                Spacer()
                if calendar.isLoading {
                    Text("Loading…").font(Typo.sans(11.5)).foregroundStyle(theme.muted)
                } else if !calendar.events.isEmpty {
                    Text("\(calendar.events.count) events")
                        .font(Typo.sans(11.5))
                        .foregroundStyle(theme.muted)
                }
                Button { Task { await calendar.refresh() } } label: {
                    Text("Refresh")
                        .font(Typo.sans(11.5, .medium))
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .hoverHighlight(theme, cornerRadius: 5)
                }
                .buttonStyle(.flat)
            }

            if calendar.needsSetup || showSourcePicker {
                setupPanel.padding(.top, 18)
            } else if calendar.events.isEmpty {
                emptyDay.padding(.top, 18)
            } else {
                timeline.padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeline: some View {
        ZStack(alignment: .topLeading) {
            // Hour rules
            VStack(spacing: 0) {
                ForEach(firstHour...lastHour, id: \.self) { hour in
                    HStack(spacing: 10) {
                        Text(String(format: "%02d:00", hour))
                            .font(Typo.mono(10.5))
                            .foregroundStyle(theme.muted)
                            .frame(width: 42, alignment: .leading)
                        Rectangle().fill(theme.lineSoft).frame(height: 1)
                    }
                    .frame(height: hourHeight, alignment: .top)
                }
            }

            // Events, positioned against the same scale
            ForEach(calendar.events) { event in
                eventBlock(event)
                    .frame(height: height(for: event))
                    .offset(x: 52, y: offset(for: event))
            }
        }
        .frame(height: CGFloat(lastHour - firstHour + 1) * hourHeight, alignment: .topLeading)
    }

    private func offset(for event: DayEvent) -> CGFloat {
        let cal = Calendar.current
        let minutes = CGFloat(cal.component(.hour, from: event.start) * 60
            + cal.component(.minute, from: event.start))
        return (minutes - CGFloat(firstHour * 60)) / 60 * hourHeight
    }

    private func height(for event: DayEvent) -> CGFloat {
        let minutes = CGFloat(event.end.timeIntervalSince(event.start) / 60)
        return max(48, minutes / 60 * hourHeight - 4)
    }

    private func eventBlock(_ event: DayEvent) -> some View {
        let isSelected = event.id == state.selectedEventId
        return Button {
            state.selectedEventId = isSelected ? nil : event.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? theme.onAccent.opacity(0.5) : theme.accentDeep)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(Typo.sans(12.5, .medium))
                        .lineLimit(1)
                    Text("\(Clock.hhmm(event.start)) – \(Clock.hhmm(event.end))")
                        .font(Typo.sans(11))
                        .opacity(0.7)
                }
                Spacer(minLength: 4)
                if !event.relative.isEmpty {
                    Text(event.relative)
                        .font(Typo.mono(10))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(isSelected ? theme.onAccent : theme.text)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.accent : theme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(event.isPast ? 0.55 : 1)
        }
        .buttonStyle(.flat)
        .padding(.trailing, 8)
    }

    /// A configured calendar with a free day shouldn't be shouted at with the
    /// whole setup panel — just say so, and offer a way back to the picker.
    private var emptyDay: some View {
        HStack(spacing: 12) {
            Text(calendar.status ?? "Nothing scheduled today.")
                .font(Typo.sans(12.5))
                .foregroundStyle(theme.muted)
            Button { showSourcePicker = true } label: {
                Text("Change source")
                    .font(Typo.sans(11.5, .medium))
                    .foregroundStyle(theme.accentDeep)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .hoverHighlight(theme, cornerRadius: 5)
            }
            .buttonStyle(.flat)
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: 520, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
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
                    let selected = calendar.backend == option
                    Button { calendar.backend = option } label: {
                        Text(option.label)
                            .font(Typo.sans(11.5, .medium))
                            .foregroundStyle(selected ? theme.onAccent : theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(selected ? theme.accent : .clear)
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

            if showSourcePicker && !calendar.needsSetup {
                Button { showSourcePicker = false } label: {
                    Text("Done")
                        .font(Typo.sans(11.5, .medium))
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .hoverHighlight(theme, cornerRadius: 5)
                }
                .buttonStyle(.flat)
            }
        }
        .padding(20)
        .frame(maxWidth: 520, alignment: .leading)
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
                .onSubmit { Task { await calendar.refresh() } }

            Button { Task { await calendar.refresh() } } label: {
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
                    pillLabel(calendar.importPath == nil ? "Choose export…" : "Change…", filled: calendar.importPath == nil)
                }
                .buttonStyle(.flat)

                if calendar.importPath != nil {
                    Button { Task { await calendar.refresh() } } label: {
                        pillLabel("Reload", filled: true)
                    }
                    .buttonStyle(.flat)
                }
            }

            if let description = calendar.importDescription {
                Text("Reading \(description)")
                    .font(Typo.mono(11))
                    .foregroundStyle(theme.muted)
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
        panel.allowedContentTypes = [
            UTType(filenameExtension: "ics") ?? .data,
            .zip,
            .folder,
        ]
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

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 14) {
            if let event = selected {
                eventDetail(event)
            } else {
                Text("Pick an event to see guests, location and take notes against it.")
                    .font(Typo.sans(12.5))
                    .foregroundStyle(theme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.line, lineWidth: 1)
                    )
            }

            if !calendar.calendarCounts.isEmpty {
                calendarsCard
            }
        }
    }

    private func eventDetail(_ event: DayEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EVENT")
                .font(Typo.sans(10)).kerning(1.6)
                .foregroundStyle(theme.muted)
            Text(event.title)
                .font(Typo.sans(16, .semibold))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            Text("\(Clock.hhmm(event.start)) – \(Clock.hhmm(event.end))"
                + (event.relative.isEmpty ? " · ended" : " · \(event.relative)"))
                .font(Typo.sans(12.5))
                .foregroundStyle(theme.muted)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 9) {
                detailRow("Where", event.location)
                detailRow("Organizer", event.organizer)
                if !event.attendees.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Text("Guests")
                            .font(Typo.sans(11))
                            .foregroundStyle(theme.muted)
                            .frame(width: 62, alignment: .leading)
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(event.attendees, id: \.self) { name in
                                HStack(spacing: 6) {
                                    Text(String(name.prefix(1)).uppercased())
                                        .font(Typo.sans(9.5, .semibold))
                                        .foregroundStyle(theme.accentDeep)
                                        .frame(width: 18, height: 18)
                                        .background(theme.accentSoft)
                                        .clipShape(Circle())
                                    Text(name).font(Typo.sans(11.5)).foregroundStyle(theme.text)
                                }
                                .padding(.trailing, 8).padding(.vertical, 3).padding(.leading, 3)
                                .background(theme.field)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(theme.lineSoft).frame(height: 1) }

            HStack(spacing: 6) {
                Button { takeNotes(on: event) } label: {
                    Text("Take notes")
                        .font(Typo.sans(11.5, .semibold))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.flat)

                Button { addFollowUp(for: event) } label: {
                    Text("Add follow-up")
                        .font(Typo.sans(11.5, .medium))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.flat)
            }
            .padding(.top, 16)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(Typo.sans(11))
                .foregroundStyle(theme.muted)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(Typo.sans(12.5))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var calendarsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CALENDARS")
                .font(Typo.sans(10)).kerning(1.6)
                .foregroundStyle(theme.muted)
            VStack(spacing: 9) {
                ForEach(calendar.calendarCounts, id: \.name) { entry in
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.accentDeep)
                            .frame(width: 8, height: 8)
                        Text(entry.name).font(Typo.sans(12.5)).foregroundStyle(theme.text)
                        Spacer()
                        Text("\(entry.count)").font(Typo.mono(11)).foregroundStyle(theme.muted)
                    }
                }
            }
            .padding(.top, 11)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }

    // MARK: - Actions

    /// `selNoteAction` (:988) — a note titled after the meeting, opened ready to type.
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

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f.string(from: Date())
    }
}
