import SwiftUI

/// Calendar arithmetic stays in the user's calendar/time zone, including DST.
struct DatePickerCalendar {
    var calendar: Calendar = .autoupdatingCurrent

    func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }
    func movingMonth(_ date: Date, by offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: monthStart(date))!
    }
    func addingDays(_ offset: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
    }
    func days(in month: Date) -> [Date] {
        let start = monthStart(month)
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let first = addingDays(-leading, to: start)
        return (0..<42).map { addingDays($0, to: first) }
    }
    var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
    }
    func string(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// Explicit palette tokens style both the field and every part of its popover.
struct ThemedDatePicker: View {
    @Binding var selection: Date?
    @Binding var isPresented: Bool
    let theme: Theme
    private let dates = DatePickerCalendar()

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar").foregroundStyle(theme.accentDeep)
                Text(selection.map { dates.string($0, template: "yMMMd") } ?? "No due date")
                    .foregroundStyle(selection == nil ? theme.muted : theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(theme.muted)
            }.font(Typo.sans(12)).padding(9).background(theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(isPresented ? theme.accentDeep : theme.line, lineWidth: 1) }
                .contentShape(Rectangle())
        }.buttonStyle(.flat).modifier(DatePickerFocus(theme: theme)).accessibilityLabel("Due date")
            .accessibilityValue(selection.map { dates.string($0, template: "yMMMMd") } ?? "Not set")
            .help("Choose a due date")
            .popover(isPresented: $isPresented, arrowEdge: .leading) {
                ThemedDateCalendar(selection: $selection, theme: theme, onClose: { isPresented = false })
                    .presentationBackground(theme.surface)
            }
    }
}

struct ThemedDateCalendar: View {
    @Binding var selection: Date?
    let theme: Theme
    let dates: DatePickerCalendar
    let today: Date
    let onClose: () -> Void
    @State private var month: Date
    @FocusState private var focusedDay: Date?

    init(selection: Binding<Date?>, theme: Theme, dates: DatePickerCalendar = DatePickerCalendar(),
         today: Date = Clock.now(), onClose: @escaping () -> Void) {
        _selection = selection; self.theme = theme; self.dates = dates
        self.today = dates.calendar.startOfDay(for: today); self.onClose = onClose
        _month = State(initialValue: dates.monthStart(selection.wrappedValue ?? today))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(dates.string(month, template: "yMMMM")).font(Typo.sans(14, .semibold))
                    .foregroundStyle(theme.text).accessibilityAddTraits(.isHeader)
                Spacer()
                navigation("Previous month", symbol: "chevron.left", offset: -1)
                navigation("Next month", symbol: "chevron.right", offset: 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(dates.weekdays[index]).font(Typo.sans(10, .medium)).foregroundStyle(theme.muted)
                        .frame(height: 22).accessibilityHidden(true)
                }
                ForEach(dates.days(in: month), id: \.self) { date in day(date) }
            }
            Rectangle().fill(theme.line).frame(height: 1)
            HStack(spacing: 6) {
                shortcut("Today", offset: 0)
                shortcut("Tomorrow", offset: 1)
                shortcut("Next week", offset: 7)
            }
            HStack {
                Text(selection.map { dates.string($0, template: "yMMMd") } ?? "No due date")
                    .font(Typo.sans(11)).foregroundStyle(theme.muted)
                Spacer()
                Button("Clear date") { selection = nil; onClose() }
                    .font(Typo.sans(11, .medium)).foregroundStyle(theme.accentDeep)
                    .buttonStyle(.flat).modifier(DatePickerFocus(theme: theme)).disabled(selection == nil)
                    .opacity(selection == nil ? 0.45 : 1)
            }
        }.padding(16).frame(width: 292).background(theme.surface)
            .tint(theme.accentDeep).preferredColorScheme(theme.isDark ? .dark : .light)
            .onExitCommand(perform: onClose)
            .onAppear { focusedDay = dates.calendar.startOfDay(for: selection ?? today) }
            .onKeyPress(.leftArrow) { moveFocus(-1); return .handled }
            .onKeyPress(.rightArrow) { moveFocus(1); return .handled }
            .onKeyPress(.upArrow) { moveFocus(-7); return .handled }
            .onKeyPress(.downArrow) { moveFocus(7); return .handled }
            .onChange(of: selection) { _, value in
                if let value { month = dates.monthStart(value) }
            }
    }
    private func navigation(_ label: String, symbol: String, offset: Int) -> some View {
        Button {
            month = dates.movingMonth(month, by: offset)
            // Arrow-key navigation continues in the newly displayed month.
            focusedDay = month
        } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.text).frame(width: 26, height: 26)
                .hoverHighlight(theme, cornerRadius: 5)
        }.buttonStyle(.flat).modifier(DatePickerFocus(theme: theme)).help(label).accessibilityLabel(label)
    }
    private func day(_ date: Date) -> some View {
        let selected = selection.map { dates.calendar.isDate($0, inSameDayAs: date) } ?? false
        let isToday = dates.calendar.isDate(date, inSameDayAs: today)
        let inMonth = dates.calendar.isDate(date, equalTo: month, toGranularity: .month)
        return Button { select(date) } label: {
            Text(dates.string(date, template: "d")).font(Typo.sans(12, selected || isToday ? .semibold : .regular))
                .foregroundStyle(selected ? theme.onAccent : (inMonth ? theme.text : theme.muted))
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(selected ? theme.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(focusedDay == date || (isToday && !selected) ? theme.accentDeep : Color.clear,
                                lineWidth: focusedDay == date ? 2 : 1)
                }
                .hoverHighlight(theme, cornerRadius: 6)
        }.buttonStyle(.flat).focused($focusedDay, equals: date).focusEffectDisabled()
            .accessibilityLabel(dates.string(date, template: "yMMMMEEEEd") + (isToday ? ", Today" : ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func shortcut(_ title: String, offset: Int) -> some View {
        Button { select(dates.addingDays(offset, to: today)) } label: {
            Text(title).font(Typo.sans(10.5, .medium)).foregroundStyle(theme.accentDeep)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(theme.accentSoft).clipShape(RoundedRectangle(cornerRadius: 5))
                .hoverHighlight(theme, cornerRadius: 5)
        }.buttonStyle(.flat).modifier(DatePickerFocus(theme: theme))
    }
    private func select(_ date: Date) {
        selection = dates.calendar.startOfDay(for: date)
        onClose()
    }
    private func moveFocus(_ offset: Int) {
        let next = dates.addingDays(offset, to: focusedDay ?? selection ?? month)
        month = dates.monthStart(next)
        focusedDay = next
    }
}

/// AppKit's default keyboard focus ring otherwise introduces system blue.
private struct DatePickerFocus: ViewModifier {
    let theme: Theme
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).focusEffectDisabled().overlay {
            RoundedRectangle(cornerRadius: 6).stroke(focused ? theme.accentDeep : Color.clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}
