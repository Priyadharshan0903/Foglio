import Foundation
@testable import FoglioCore

func icsTests() {
    let cal = Calendar.current

    /// A fixed local date so these don't drift with the day they run on.
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    /// Local floating time, the form Google writes with a TZID.
    func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f.string(from: date)
    }

    func wrap(_ body: String) -> String {
        "BEGIN:VCALENDAR\nX-WR-CALNAME:Work\n\(body)\nEND:VCALENDAR"
    }

    func event(start: Date, end: Date, extra: [String] = []) -> String {
        ([
            "BEGIN:VEVENT",
            "UID:evt-1",
            "SUMMARY:Platform standup",
            "LOCATION:Google Meet",
            "DTSTART:\(stamp(start))",
            "DTEND:\(stamp(end))",
        ] + extra + ["END:VEVENT"]).joined(separator: "\n")
    }

    let monday = date(2026, 3, 2)             // anchor
    let mondayEnd = date(2026, 3, 2, 9, 30)

    Check.suite("ICS — a single event") {
        let events = ICS.events(from: wrap(event(start: monday, end: mondayEnd)), on: monday)
        Check.equal(events.count, 1, "the event is found on its own day")
        Check.equal(events.first?.summary, "Platform standup", "summary is read")
        Check.equal(events.first?.location, "Google Meet", "location is read")
        Check.equal(events.first?.calendarName, "Work", "X-WR-CALNAME names the calendar")

        let nextDay = ICS.events(from: wrap(event(start: monday, end: mondayEnd)),
                                 on: cal.date(byAdding: .day, value: 1, to: monday)!)
        Check.equal(nextDay.count, 0, "a one-off does not repeat")
    }

    Check.suite("ICS — awkward input") {
        // RFC 5545 folds long lines with a leading space; unfolding must rejoin.
        let folded = wrap("""
        BEGIN:VEVENT
        UID:evt-2
        SUMMARY:Operator design review with the
          whole platform team
        DTSTART:\(stamp(monday))
        DTEND:\(stamp(mondayEnd))
        END:VEVENT
        """)
        Check.equal(
            ICS.events(from: folded, on: monday).first?.summary,
            "Operator design review with the whole platform team",
            "folded lines are rejoined"
        )

        // Commas and semicolons arrive escaped.
        let escaped = wrap(event(start: monday, end: mondayEnd, extra: [
            "SUMMARY:Ship it\\, then celebrate\\; maybe",
        ]))
        Check.equal(
            ICS.events(from: escaped, on: monday).first?.summary,
            "Ship it, then celebrate; maybe",
            "escaped punctuation is unescaped"
        )

        // Names come from CN, not the mailto address.
        let people = wrap(event(start: monday, end: mondayEnd, extra: [
            "ORGANIZER;CN=Priya S.:mailto:priya@example.com",
            "ATTENDEE;CN=Arun K.:mailto:arun@example.com",
            "ATTENDEE:mailto:chen@example.com",
        ]))
        let parsed = ICS.events(from: people, on: monday).first
        Check.equal(parsed?.organizer, "Priya S.", "organizer uses CN")
        Check.equal(parsed?.attendees.first, "Arun K.", "attendee uses CN")
        Check.equal(parsed?.attendees.last, "chen@example.com", "falls back to the address")

        // All-day events are excluded from a timed day view.
        let allDay = wrap("""
        BEGIN:VEVENT
        UID:evt-3
        SUMMARY:Company holiday
        DTSTART;VALUE=DATE:20260302
        DTEND;VALUE=DATE:20260303
        END:VEVENT
        """)
        Check.equal(ICS.events(from: allDay, on: monday).count, 0, "all-day events are skipped")
    }

    Check.suite("ICS — UTC and time zones") {
        let utc = wrap("""
        BEGIN:VEVENT
        UID:evt-4
        SUMMARY:UTC meeting
        DTSTART:20260302T120000Z
        DTEND:20260302T123000Z
        END:VEVENT
        """)
        let parsed = ICS.parse(utc).first
        // 12:00 UTC is a fixed instant regardless of where the test runs.
        Check.equal(
            parsed?.start.timeIntervalSince1970,
            Date(timeIntervalSince1970: 1_772_452_800).timeIntervalSince1970,
            "a Z suffix is read as UTC"
        )

        let zoned = wrap("""
        BEGIN:VEVENT
        UID:evt-5
        SUMMARY:Zoned meeting
        DTSTART;TZID=UTC:20260302T120000
        DTEND;TZID=UTC:20260302T123000
        END:VEVENT
        """)
        Check.equal(
            ICS.parse(zoned).first?.start,
            ICS.parse(utc).first?.start,
            "TZID=UTC matches a Z suffix"
        )
    }

    Check.suite("ICS — daily recurrence") {
        let ics = wrap(event(start: monday, end: mondayEnd, extra: ["RRULE:FREQ=DAILY"]))

        for offset in [0, 1, 5, 40] {
            let day = cal.date(byAdding: .day, value: offset, to: monday)!
            Check.equal(
                ICS.events(from: ics, on: day).count, 1,
                "a daily meeting appears \(offset) days on"
            )
        }
        Check.equal(
            ICS.events(from: ics, on: cal.date(byAdding: .day, value: -1, to: monday)!).count,
            0,
            "and never before it started"
        )

        let everyOther = wrap(event(start: monday, end: mondayEnd, extra: ["RRULE:FREQ=DAILY;INTERVAL=2"]))
        Check.equal(ICS.events(from: everyOther, on: monday).count, 1, "INTERVAL=2 occurs on day 0")
        Check.equal(
            ICS.events(from: everyOther, on: cal.date(byAdding: .day, value: 1, to: monday)!).count,
            0, "skips day 1"
        )
        Check.equal(
            ICS.events(from: everyOther, on: cal.date(byAdding: .day, value: 2, to: monday)!).count,
            1, "returns on day 2"
        )
    }

    Check.suite("ICS — weekly recurrence with BYDAY") {
        // A standup on the anchor's own weekday — the common real case.
        let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        let anchorDay = codes[cal.component(.weekday, from: monday) - 1]
        let ics = wrap(event(start: monday, end: mondayEnd, extra: ["RRULE:FREQ=WEEKLY;BYDAY=\(anchorDay)"]))

        Check.equal(ICS.events(from: ics, on: monday).count, 1, "occurs on the start day")
        Check.equal(
            ICS.events(from: ics, on: cal.date(byAdding: .day, value: 7, to: monday)!).count,
            1, "and the same weekday next week"
        )
        Check.equal(
            ICS.events(from: ics, on: cal.date(byAdding: .day, value: 1, to: monday)!).count,
            0, "but not the day after"
        )

        // Every weekday, as most standups are configured.
        let weekdays = wrap(event(start: monday, end: mondayEnd, extra: ["RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"]))
        var weekdayHits = 0
        for offset in 0..<7 {
            let day = cal.date(byAdding: .day, value: offset, to: monday)!
            weekdayHits += ICS.events(from: weekdays, on: day).count
        }
        Check.equal(weekdayHits, 5, "a Mon–Fri standup occurs five times a week")
    }

    Check.suite("ICS — recurrence limits") {
        let counted = wrap(event(start: monday, end: mondayEnd, extra: ["RRULE:FREQ=DAILY;COUNT=3"]))
        Check.equal(ICS.events(from: counted, on: monday).count, 1, "COUNT includes the first")
        Check.equal(
            ICS.events(from: counted, on: cal.date(byAdding: .day, value: 2, to: monday)!).count,
            1, "and the third"
        )
        Check.equal(
            ICS.events(from: counted, on: cal.date(byAdding: .day, value: 3, to: monday)!).count,
            0, "but stops after COUNT is reached"
        )

        let until = cal.date(byAdding: .day, value: 2, to: monday)!
        let bounded = wrap(event(start: monday, end: mondayEnd, extra: ["RRULE:FREQ=DAILY;UNTIL=\(stamp(until))"]))
        Check.equal(ICS.events(from: bounded, on: until).count, 1, "UNTIL is inclusive of its day")
        Check.equal(
            ICS.events(from: bounded, on: cal.date(byAdding: .day, value: 3, to: monday)!).count,
            0, "and excludes everything after"
        )

        // A cancelled instance of a recurring meeting.
        let skipped = cal.date(byAdding: .day, value: 1, to: monday)!
        let withException = wrap(event(start: monday, end: mondayEnd, extra: [
            "RRULE:FREQ=DAILY",
            "EXDATE:\(stamp(skipped))",
        ]))
        Check.equal(ICS.events(from: withException, on: monday).count, 1, "other days are unaffected")
        Check.equal(ICS.events(from: withException, on: skipped).count, 0, "EXDATE cancels that instance")
    }

    Check.suite("ICS — occurrences keep their duration and identity") {
        let ics = wrap(event(start: monday, end: mondayEnd, extra: ["RRULE:FREQ=DAILY"]))
        let later = cal.date(byAdding: .day, value: 3, to: monday)!
        let occurrence = ICS.events(from: ics, on: later).first

        Check.equal(occurrence?.duration, 1800, "a 30-minute meeting stays 30 minutes")
        Check.equal(
            cal.component(.hour, from: occurrence?.start ?? Date()), 9,
            "and keeps its start time"
        )
        Check.expect(occurrence?.recurrence == nil, "an expanded occurrence is no longer recurring")

        // DayEvent ids must differ per occurrence or SwiftUI collapses them.
        let a = DayEvent(ICS.events(from: ics, on: monday).first!)
        let b = DayEvent(ICS.events(from: ics, on: later).first!)
        Check.expect(a.id != b.id, "each occurrence gets a distinct id")
    }
}

@MainActor
func calendarURLTests() {
    Check.suite("Calendar URL — normalising a pasted address") {
        let real = "https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/private-deadbeef/basic.ics"

        // Copying from Google's settings page usually drags a newline along.
        // `.whitespaces` didn't strip that, which broke URL parsing outright.
        Check.equal(CalendarSource.normalize("\(real)\n"), real, "a trailing newline is stripped")
        Check.equal(CalendarSource.normalize("  \(real)  "), real, "surrounding spaces are stripped")
        Check.equal(CalendarSource.normalize("<\(real)>"), real, "angle brackets are stripped")
        Check.equal(CalendarSource.normalize("\"\(real)\""), real, "quotes are stripped")

        // Google offers the same feed as webcal://, which URLSession can't fetch.
        Check.equal(
            CalendarSource.normalize("webcal://calendar.google.com/calendar/ical/x/private-y/basic.ics"),
            "https://calendar.google.com/calendar/ical/x/private-y/basic.ics",
            "webcal:// becomes https://"
        )
        Check.equal(CalendarSource.normalize(""), "", "an empty string stays empty")
    }

    Check.suite("Calendar URL — explaining failures") {
        let publicURL = "https://calendar.google.com/calendar/ical/me%40gmail.com/public/basic.ics"
        let secretURL = "https://calendar.google.com/calendar/ical/me%40gmail.com/private-abc/basic.ics"

        // The case actually hit: a 404 on the public address of a private calendar.
        let publicMessage = CalendarSource.explain(status: 404, url: publicURL)
        Check.expect(publicMessage.contains("Public address"), "404 on a public URL names the real cause")
        Check.expect(publicMessage.contains("Secret address"), "and says where to find the right one")

        // A 404 on a secret address means something else entirely.
        let secretMessage = CalendarSource.explain(status: 404, url: secretURL)
        Check.expect(!secretMessage.contains("Public address"), "404 on a secret URL doesn't blame the public one")
        Check.expect(secretMessage.contains("reset"), "it suggests the address may have been reset")

        Check.expect(
            CalendarSource.explain(status: 403, url: secretURL).contains("refused"),
            "403 reads as access refused"
        )
        Check.expect(
            CalendarSource.explain(status: 500, url: secretURL).contains("500"),
            "an unexpected status still reports its code"
        )
    }
}

func importerTests() {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("foglio-import-\(UUID().uuidString)")
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    func sampleICS(_ summary: String) -> String {
        """
        BEGIN:VCALENDAR
        X-WR-CALNAME:Work
        BEGIN:VEVENT
        UID:evt-\(summary)
        SUMMARY:\(summary)
        DTSTART:20260302T090000
        DTEND:20260302T093000
        END:VEVENT
        END:VCALENDAR
        """
    }

    Check.suite("Import — a plain .ics file") {
        let file = root.appendingPathComponent("plain.ics")
        try? sampleICS("Standup").write(to: file, atomically: true, encoding: .utf8)

        let text = (try? ICSImporter.read(file)) ?? ""
        Check.expect(text.contains("Standup"), "a .ics file is read directly")
        Check.equal(ICSImporter.describe(file), "plain.ics", "described by filename")
    }

    Check.suite("Import — Google's zip export") {
        // Google hands you `<address>.ical.zip` containing one .ics per calendar.
        // Pointing at the zip must work, or the only route left to this user fails.
        let staging = root.appendingPathComponent("staging")
        try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try? sampleICS("Design review").write(
            to: staging.appendingPathComponent("primary.ics"), atomically: true, encoding: .utf8
        )

        let zip = root.appendingPathComponent("priya.ical.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", "-q", zip.path, staging.appendingPathComponent("primary.ics").path]
        try? process.run()
        process.waitUntilExit()

        guard fm.fileExists(atPath: zip.path) else {
            Check.expect(false, "could not build a test zip")
            return
        }

        let text = (try? ICSImporter.read(zip)) ?? ""
        Check.expect(text.contains("BEGIN:VCALENDAR"), "the zip yields calendar text")
        Check.expect(text.contains("Design review"), "and the event inside it")
    }

    Check.suite("Import — watching a folder") {
        let downloads = root.appendingPathComponent("downloads")
        try? fm.createDirectory(at: downloads, withIntermediateDirectories: true)

        let older = downloads.appendingPathComponent("old.ics")
        try? sampleICS("Old meeting").write(to: older, atomically: true, encoding: .utf8)
        try? fm.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: older.path
        )

        // Re-exporting doesn't overwrite; Google adds " (1)". The newest wins.
        let newer = downloads.appendingPathComponent("new (1).ics")
        try? sampleICS("New meeting").write(to: newer, atomically: true, encoding: .utf8)

        Check.equal(
            ICSImporter.newestExport(in: downloads)?.lastPathComponent,
            "new (1).ics",
            "the most recent export is chosen"
        )
        let text = (try? ICSImporter.read(downloads)) ?? ""
        Check.expect(text.contains("New meeting"), "a folder resolves to its newest export")
        Check.expect(!text.contains("Old meeting"), "and not the stale one")

        // Unrelated downloads must not be mistaken for a calendar.
        try? "not a calendar".write(
            to: downloads.appendingPathComponent("photos.zip"), atomically: true, encoding: .utf8
        )
        Check.equal(
            ICSImporter.newestExport(in: downloads)?.lastPathComponent,
            "new (1).ics",
            "a non-calendar zip is ignored"
        )

        let empty = root.appendingPathComponent("empty")
        try? fm.createDirectory(at: empty, withIntermediateDirectories: true)
        Check.expect(ICSImporter.newestExport(in: empty) == nil, "an empty folder finds nothing")
        Check.expect(
            ((try? ICSImporter.read(empty)) == nil),
            "and reading it reports a failure rather than returning junk"
        )
    }
}

@MainActor
func snapshotAgeTests() {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("foglio-age-\(UUID().uuidString)")
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    func writeExport(named name: String, ageInHours: Double) -> URL {
        let url = root.appendingPathComponent(name)
        try? "BEGIN:VCALENDAR\nEND:VCALENDAR".write(to: url, atomically: true, encoding: .utf8)
        try? fm.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -ageInHours * 3600)],
            ofItemAtPath: url.path
        )
        return url
    }

    Check.suite("Snapshot age — reported from the file being read") {
        let fresh = writeExport(named: "fresh.ics", ageInHours: 0)
        Check.expect(ICSImporter.exportedAt(fresh) != nil, "a file reports when it was written")

        // For a folder it must describe the export actually in use, not the folder.
        let old = writeExport(named: "old.ics", ageInHours: 50)
        _ = old
        let newestAge = ICSImporter.exportedAt(root)
        Check.expect(
            newestAge.map { Date().timeIntervalSince($0) < 3600 } == true,
            "a folder reports the age of its newest export, not its oldest"
        )
    }

    Check.suite("Snapshot age — staleness only applies to exports") {
        let source = CalendarSource()

        // A live backend is never "stale" — there's nothing to re-export.
        source.backend = .subscription
        Check.expect(!source.snapshotIsStale, "a subscription URL is never flagged stale")

        source.backend = .file
        source.chooseImport(at: writeExport(named: "recent.ics", ageInHours: 1))
        Check.expect(!source.snapshotIsStale, "an export from an hour ago is fine")
        Check.equal(source.snapshotAge, "1h ago", "and its age reads in hours")

        source.chooseImport(at: writeExport(named: "ancient.ics", ageInHours: 30))
        Check.expect(source.snapshotIsStale, "an export from yesterday is flagged stale")
        Check.equal(source.snapshotAge, "1d ago", "and its age reads in days")
    }
}

@MainActor
func weekRangeTests() {
    var cal = Calendar.current
    cal.firstWeekday = 2

    Check.suite("Calendar week — the visible range") {
        // A Wednesday, to prove the week is derived rather than "today + 7".
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 15))!
        let week = CalendarSource.week(containing: wednesday)

        Check.equal(cal.component(.weekday, from: week.start), 2, "weeks start on Monday")
        Check.expect(week.contains(wednesday), "the anchor day is inside its own week")
        Check.equal(Int(week.duration / 86_400), 7, "a week is seven days long")

        // Sunday must belong to the week that started the previous Monday, which
        // a Sunday-first calendar would get wrong.
        let sunday = cal.date(byAdding: .day, value: 4, to: wednesday)!
        Check.equal(
            CalendarSource.week(containing: sunday).start,
            week.start,
            "Sunday belongs to the week that began on Monday"
        )

        let nextMonday = cal.date(byAdding: .day, value: 5, to: wednesday)!
        Check.expect(
            CalendarSource.week(containing: nextMonday).start > week.start,
            "the following Monday starts a new week"
        )
    }

    Check.suite("ICS — expanding a whole week in one parse") {
        func stamp(_ d: Date) -> String {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd'T'HHmmss"; return f.string(from: d)
        }
        let monday = cal.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 9))!
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:standup
        SUMMARY:Standup
        DTSTART:\(stamp(monday))
        DTEND:\(stamp(monday.addingTimeInterval(900)))
        RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
        END:VEVENT
        END:VCALENDAR
        """

        let week = CalendarSource.week(containing: monday)
        let events = ICS.events(from: ics, in: week)
        Check.equal(events.count, 5, "a weekday standup expands to five in a week range")
        Check.expect(
            events.map(\.start) == events.map(\.start).sorted(),
            "results come back in chronological order"
        )
        // Each occurrence needs its own identity or the grid collapses them.
        let ids = Set(events.map { DayEvent($0).id })
        Check.equal(ids.count, 5, "each occurrence keeps a distinct id")
    }
}
