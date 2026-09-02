import Foundation
@testable import FoglioCore

func weekTests() {
    let cal = Calendar.current
    let now = Date()

    func daysAgo(_ n: Int, hour: Int = 12) -> Date {
        let day = cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: now))!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    Check.suite("Week summary — shape") {
        let summary = WeekSummary.build(log: [], noteCount: 0, now: now)
        Check.equal(summary.days.count, 7, "always seven days")
        Check.equal(summary.days.last?.label, "Today", "the last bar is today")
        Check.expect(summary.days.last?.isToday == true, "and is flagged as today")
        Check.expect(
            summary.days.dropLast().allSatisfy { !$0.isToday },
            "no other day claims to be today"
        )
        Check.equal(summary.entries, 0, "an empty log counts nothing")
    }

    Check.suite("Week summary — bucketing") {
        let log = [
            LogEntry(text: "a", kind: .task, at: daysAgo(0)),
            LogEntry(text: "b", kind: .focus, at: daysAgo(0)),
            LogEntry(text: "c", kind: .manual, at: daysAgo(2)),
            LogEntry(text: "d", kind: .focus, at: daysAgo(6)),
            // Outside the window — must be excluded from both bars and totals.
            LogEntry(text: "old", kind: .task, at: daysAgo(9)),
        ]
        let summary = WeekSummary.build(log: log, noteCount: 4, now: now)

        Check.equal(summary.entries, 4, "only entries inside the seven-day window count")
        Check.equal(summary.focusBlocks, 2, "focus entries are counted separately")
        Check.equal(summary.notes, 4, "note count passes through")
        Check.equal(summary.days.last?.count, 2, "today's bar has two entries")
        Check.equal(summary.days.first?.count, 1, "six days ago has one")
        Check.equal(summary.days[4].count, 1, "two days ago has one")
        Check.equal(summary.days[1].count, 0, "a quiet day is zero, not missing")
    }

    Check.suite("Week summary — bars") {
        let log = [
            LogEntry(text: "a", kind: .task, at: daysAgo(0)),
            LogEntry(text: "b", kind: .task, at: daysAgo(0)),
            LogEntry(text: "c", kind: .task, at: daysAgo(3)),
        ]
        let summary = WeekSummary.build(log: log, noteCount: 0, now: now)

        let today = summary.days.last!
        let quiet = summary.days[1]

        Check.expect(summary.isPeak(today), "the busiest day is the peak")
        Check.expect(!summary.isPeak(quiet), "an empty day is never the peak")
        Check.expect(
            summary.barHeight(for: today) > summary.barHeight(for: quiet),
            "a busier day draws a taller bar"
        )
        Check.equal(summary.barHeight(for: quiet), 8, "an empty day still draws the 8pt stub")

        // With no entries at all, nothing should divide by zero or be the peak.
        let empty = WeekSummary.build(log: [], noteCount: 0, now: now)
        Check.equal(empty.barHeight(for: empty.days[0]), 8, "an empty week has no division by zero")
        Check.expect(!empty.isPeak(empty.days[0]), "an empty week has no peak day")
    }

    Check.suite("Calendar events — relative labels") {
        func event(startingIn minutes: Int, lasting: Int = 30) -> DayEvent {
            let start = Date().addingTimeInterval(Double(minutes) * 60)
            return DayEvent(
                id: "x", title: "Standup", start: start,
                end: start.addingTimeInterval(Double(lasting) * 60),
                location: "Meet", organizer: "You", attendees: [], calendar: "Work"
            )
        }

        Check.equal(event(startingIn: 25).relative, "in 25 min", "upcoming reads in minutes")
        Check.equal(event(startingIn: 120).relative, "in 2h", "a round hour drops the minutes")
        Check.equal(event(startingIn: 90).relative, "in 1h 30m", "otherwise both are shown")
        Check.equal(event(startingIn: 0).relative, "now", "a meeting starting now says so")
        Check.expect(
            event(startingIn: -10).relative.hasPrefix("started "),
            "one in progress says how long ago it began"
        )
        Check.equal(event(startingIn: -120, lasting: 30).relative, "", "a finished meeting says nothing")
        Check.expect(event(startingIn: -120, lasting: 30).isPast, "and is marked past")
    }
}

@MainActor
func meetingNudgeTests() {
    func event(startingIn minutes: Int, lasting: Int = 30, at location: String = "No location") -> DayEvent {
        let start = Date().addingTimeInterval(Double(minutes) * 60)
        return DayEvent(
            id: "evt-\(minutes)", title: "Platform standup", start: start,
            end: start.addingTimeInterval(Double(lasting) * 60),
            location: location, organizer: "Arun K.", attendees: ["Arun K."], calendar: "Work"
        )
    }

    Check.suite("Meeting nudge — the Join link") {
        // Only offer Join when there's somewhere to go; a dead button is worse
        // than no button.
        Check.expect(
            MeetingAlertView.joinURL(for: event(startingIn: 5, at: "https://meet.google.com/abc-defg-hij")) != nil,
            "a Google Meet link is offered"
        )
        Check.expect(
            MeetingAlertView.joinURL(for: event(startingIn: 5, at: "Join at https://zoom.us/j/123 please")) != nil,
            "a Zoom link is found inside surrounding text"
        )
        Check.expect(
            MeetingAlertView.joinURL(for: event(startingIn: 5, at: "Meeting room 4B")) == nil,
            "a physical room offers no Join"
        )
        Check.expect(
            MeetingAlertView.joinURL(for: event(startingIn: 5, at: "https://example.com/notes")) == nil,
            "an unrelated link is not treated as a conference"
        )
        Check.expect(
            MeetingAlertView.joinURL(for: event(startingIn: 5, at: "No location")) == nil,
            "no location offers no Join"
        )
    }

    Check.suite("Meeting nudge — dismissal is per meeting") {
        // The design's dismissAlert (:927) set one flag, so dismissing a single
        // nudge silently killed every later one. Dismissal is per event here.
        let state = AppState()
        let first = event(startingIn: 5)
        let second = event(startingIn: 40)

        state.dismissMeeting(first.id)
        Check.expect(state.dismissedMeetings.contains(first.id), "the dismissed meeting is remembered")
        Check.expect(
            !state.dismissedMeetings.contains(second.id),
            "a later meeting still nudges"
        )
    }
}
