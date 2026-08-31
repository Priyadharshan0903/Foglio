import Foundation
@testable import FoglioCore

func notesTests() {
    Check.suite("Relative timestamps") {
        let cal = Calendar.current

        let todayAt = cal.date(bySettingHour: 14, minute: 20, second: 0, of: Date())!
        Check.equal(Relative.label(for: todayAt), "14:20", "today shows a clock time")

        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        Check.equal(Relative.label(for: yesterday), "Yesterday", "yesterday is named")

        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: Date())!
        Check.equal(
            Relative.label(for: threeDaysAgo).count,
            3,
            "within a week shows a 3-letter weekday"
        )

        let longAgo = cal.date(byAdding: .day, value: -40, to: Date())!
        Check.expect(
            Relative.label(for: longAgo).contains(" "),
            "older than a week shows a day and month"
        )
    }

    Check.suite("Note snippets") {
        let note = Note(
            title: "Operator notes",
            body: Markdown.serialize([
                .h1("Reconcile, don't RPC"),
                .paragraph("See [[Go worker pool]] for the queue side."),
            ])
        )
        // The heading is skipped and the link brackets are stripped (:1022).
        Check.equal(
            note.snippet,
            "See Go worker pool for the queue side.",
            "snippet skips headings and strips link brackets"
        )

        let todoFirst = Note(body: Markdown.serialize([
            .h2("Heading"),
            .todo(text: "Ask Priya for staging access", checked: false),
        ]))
        Check.equal(
            todoFirst.snippet,
            "Ask Priya for staging access",
            "a todo can be the snippet when there's no paragraph"
        )

        let empty = Note(body: Markdown.serialize([.h1("Only a heading")]))
        Check.equal(empty.snippet, "", "a note with no body text has an empty snippet")
    }

    Check.suite("Note search") {
        let note = Note(
            title: "Go worker pool",
            body: "One channel in, one WaitGroup, context for cancellation."
        )
        Check.expect(note.matches(""), "an empty query matches everything")
        Check.expect(note.matches("WORKER"), "title search is case-insensitive")
        Check.expect(note.matches("waitgroup"), "body search is case-insensitive")
        Check.expect(!note.matches("kubernetes"), "non-matching query is rejected")
    }
}
