import Foundation

/// Minimal iCalendar (RFC 5545) reader — enough for a day view.
///
/// This exists because OAuth is not an option: a Google Workspace admin can set
/// API controls that reject unapproved third-party apps outright
/// (`admin_policy_enforced`), which no client id of ours can get around. The
/// private iCal address Google publishes per calendar is a plain HTTPS GET with
/// a secret in the path, so it sidesteps OAuth entirely — and the same parser
/// reads a manually exported `.ics` file when even that is disabled.
///
/// Scope is deliberate: VEVENT with DTSTART/DTEND/SUMMARY/LOCATION/ORGANIZER/
/// ATTENDEE, plus the RRULE subset real work calendars use (DAILY/WEEKLY/
/// MONTHLY/YEARLY with INTERVAL, BYDAY, COUNT, UNTIL) and EXDATE. Without
/// recurrence a daily standup would never appear, which would make the whole
/// feature useless.
enum ICS {

    // MARK: - Recurrence

    struct Recurrence: Equatable {
        enum Frequency: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

        var frequency: Frequency
        var interval: Int = 1
        /// Calendar weekday numbers (1 = Sunday).
        var byDay: Set<Int> = []
        var count: Int?
        var until: Date?
    }

    struct Event: Equatable {
        var uid: String = ""
        var summary: String = ""
        var location: String = ""
        var organizer: String = ""
        var attendees: [String] = []
        var start: Date = .distantPast
        var end: Date = .distantPast
        var isAllDay: Bool = false
        var calendarName: String = "Calendar"
        var recurrence: Recurrence?
        var exceptions: Set<Date> = []

        var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
    }

    // MARK: - Parsing

    static func parse(_ text: String, calendarName fallbackName: String = "Calendar") -> [Event] {
        let lines = unfold(text)
        var events: [Event] = []
        var current: Event?
        var calendarName = fallbackName

        for line in lines {
            let (name, params, value) = split(line)

            switch name {
            case "X-WR-CALNAME":
                calendarName = unescape(value)

            case "BEGIN" where value == "VEVENT":
                current = Event(calendarName: calendarName)

            case "END" where value == "VEVENT":
                if var event = current {
                    event.calendarName = calendarName
                    if event.end == .distantPast { event.end = event.start.addingTimeInterval(1800) }
                    if event.start != .distantPast { events.append(event) }
                }
                current = nil

            case "UID": current?.uid = value
            case "SUMMARY": current?.summary = unescape(value)
            case "LOCATION": current?.location = unescape(value)
            case "ORGANIZER": current?.organizer = displayName(params: params, value: value)
            case "ATTENDEE": current?.attendees.append(displayName(params: params, value: value))

            case "DTSTART":
                current?.isAllDay = params["VALUE"] == "DATE"
                if let date = date(from: value, params: params) { current?.start = date }

            case "DTEND":
                if let date = date(from: value, params: params) { current?.end = date }

            case "RRULE":
                current?.recurrence = recurrence(from: value, params: params)

            case "EXDATE":
                for piece in value.components(separatedBy: ",") {
                    if let date = date(from: piece, params: params) {
                        current?.exceptions.insert(date)
                    }
                }

            default:
                break
            }
        }

        return events
    }

    /// RFC 5545 folds long lines by starting continuations with a space or tab.
    private static func unfold(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if let first = raw.first, first == " " || first == "\t" {
                out[out.isEmpty ? 0 : out.count - 1] += String(raw.dropFirst())
            } else {
                out.append(raw)
            }
        }
        return out
    }

    /// `NAME;PARAM=x;PARAM2=y:value`
    private static func split(_ line: String) -> (String, [String: String], String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, [:], "") }
        let head = String(line[line.startIndex..<colon])
        let value = String(line[line.index(after: colon)...])

        let pieces = head.components(separatedBy: ";")
        var params: [String: String] = [:]
        for piece in pieces.dropFirst() {
            let kv = piece.components(separatedBy: "=")
            if kv.count == 2 { params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return (pieces[0].uppercased(), params, value)
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func displayName(params: [String: String], value: String) -> String {
        if let cn = params["CN"], !cn.isEmpty { return unescape(cn) }
        // Fall back to the address without its mailto: scheme.
        return value.replacingOccurrences(of: "mailto:", with: "")
    }

    // MARK: - Dates

    static func date(from value: String, params: [String: String]) -> Date? {
        let raw = value.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }

        var components = DateComponents()
        let digits = raw.replacingOccurrences(of: "Z", with: "")

        guard digits.count >= 8 else { return nil }
        let chars = Array(digits)
        components.year = Int(String(chars[0...3]))
        components.month = Int(String(chars[4...5]))
        components.day = Int(String(chars[6...7]))

        if digits.count >= 15 { // yyyyMMdd'T'HHmmss
            components.hour = Int(String(chars[9...10]))
            components.minute = Int(String(chars[11...12]))
            components.second = Int(String(chars[13...14]))
        }

        var calendar = Calendar(identifier: .gregorian)
        if raw.hasSuffix("Z") {
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        } else if let tzid = params["TZID"], let zone = TimeZone(identifier: tzid) {
            calendar.timeZone = zone
        } else {
            calendar.timeZone = .current
        }
        return calendar.date(from: components)
    }

    private static func recurrence(from value: String, params: [String: String]) -> Recurrence? {
        var parts: [String: String] = [:]
        for piece in value.components(separatedBy: ";") {
            let kv = piece.components(separatedBy: "=")
            if kv.count == 2 { parts[kv[0].uppercased()] = kv[1] }
        }
        guard let freqRaw = parts["FREQ"], let frequency = Recurrence.Frequency(rawValue: freqRaw.uppercased()) else {
            return nil
        }

        var rule = Recurrence(frequency: frequency)
        if let interval = parts["INTERVAL"], let n = Int(interval) { rule.interval = max(1, n) }
        if let count = parts["COUNT"], let n = Int(count) { rule.count = n }
        if let until = parts["UNTIL"] { rule.until = date(from: until, params: params) }
        if let byDay = parts["BYDAY"] {
            let map = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
            // Strip any ordinal prefix ("2MO" → "MO"); positional BYDAY is not supported.
            rule.byDay = Set(byDay.components(separatedBy: ",").compactMap {
                map[String($0.suffix(2)).uppercased()]
            })
        }
        return rule
    }

    // MARK: - Expansion

    /// Every occurrence of `event` that lands on `day`, in that day's local time.
    ///
    /// Walks forward from DTSTART rather than solving arithmetically, because
    /// COUNT can only be honoured by counting. Bounded so a long-running daily
    /// meeting can't spin.
    static func occurrences(of event: Event, on day: Date, calendar: Calendar = .current) -> [Event] {
        let dayStart = calendar.startOfDay(for: day)

        guard let rule = event.recurrence else {
            return calendar.isDate(event.start, inSameDayAs: dayStart) ? [event] : []
        }

        // A meeting that starts after the day we're asking about can't occur on it.
        guard event.start <= calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart else {
            return []
        }

        var results: [Event] = []
        var cursor = event.start
        var seen = 0
        let limit = 5000

        while seen < limit {
            if let until = rule.until, cursor > until { break }
            if let count = rule.count, seen >= count { break }
            if cursor > calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart { break }

            let matchesDay = rule.byDay.isEmpty
                || rule.byDay.contains(calendar.component(.weekday, from: cursor))

            if matchesDay {
                seen += 1
                if calendar.isDate(cursor, inSameDayAs: dayStart), !event.exceptions.contains(cursor) {
                    var occurrence = event
                    occurrence.start = cursor
                    occurrence.end = cursor.addingTimeInterval(event.duration)
                    occurrence.recurrence = nil
                    results.append(occurrence)
                }
            }

            guard let next = advance(cursor, by: rule, calendar: calendar) else { break }
            cursor = next
        }

        return results
    }

    private static func advance(_ date: Date, by rule: Recurrence, calendar: Calendar) -> Date? {
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: rule.interval, to: date)
        case .weekly:
            // With BYDAY the rule walks day by day and filters; without it, whole weeks.
            return rule.byDay.isEmpty
                ? calendar.date(byAdding: .weekOfYear, value: rule.interval, to: date)
                : calendar.date(byAdding: .day, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: rule.interval, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: rule.interval, to: date)
        }
    }

    /// All events occurring on `day`, expanded and sorted.
    static func events(from text: String, on day: Date, calendarName: String = "Calendar") -> [Event] {
        parse(text, calendarName: calendarName)
            .flatMap { occurrences(of: $0, on: day) }
            .filter { !$0.isAllDay }
            .sorted { $0.start < $1.start }
    }
}
