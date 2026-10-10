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

        let numbered = Note(body: Markdown.serialize([
            .orderedItem("Drain the node"),
            .paragraph("The order matters here."),
        ]))
        Check.equal(
            numbered.snippet,
            "The order matters here.",
            "a numbered item is a list, not a snippet"
        )

        let empty = Note(body: Markdown.serialize([.h1("Only a heading")]))
        Check.equal(empty.snippet, "", "a note with no body text has an empty snippet")
        Check.equal(Note(body: "**Important** _details_ and [notes](https://example.com)").snippet,
                    "Important details and notes", "snippets show styled prose without Markdown markers")
        Check.equal(Note(body: "file_name.txt and \u{0060}code\u{0060}").snippet,
                    "file_name.txt and code", "snippet styling preserves ordinary underscores")
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

@MainActor
func selectionTests() {
    func notes(_ n: Int) -> [Note] {
        (0..<n).map { Note(title: "Note \($0)") }
    }

    Check.suite("What the editor shows after a delete") {
        let list = notes(4)

        // The one below is what you were reaching for next.
        Check.equal(
            NotesView.survivor(after: [list[1].id], in: list, current: list[1].id),
            list[2].id,
            "deleting one selects the note below it"
        )

        // Nothing below, so fall back up rather than to the top of the list.
        Check.equal(
            NotesView.survivor(after: [list[3].id], in: list, current: list[3].id),
            list[2].id,
            "deleting the last one selects the note above it"
        )

        // A block of several: skip past all of them, not just the first.
        Check.equal(
            NotesView.survivor(after: [list[1].id, list[2].id], in: list, current: list[1].id),
            list[3].id,
            "deleting a run lands past the whole run"
        )

        Check.expect(
            NotesView.survivor(after: Set(list.map(\.id)), in: list, current: list[0].id) == nil,
            "deleting everything leaves nothing selected"
        )

        // Deleting something that isn't on screen — a selection made under a
        // different filter — mustn't move the editor off what you're reading.
        Check.equal(
            NotesView.survivor(after: [UUID()], in: list, current: list[2].id),
            list[2].id,
            "deleting a note that isn't in the list leaves the selection alone"
        )
    }

    Check.suite("Dragging notes onto a folder") {
        let a = Note(title: "A"), b = Note(title: "B"), c = Note(title: "C")

        // Dragging an unselected row is about that row only.
        Check.equal(
            NoteDrag.ids(from: NoteDrag.payload(for: a, selection: [])),
            [a.id],
            "an unselected note drags alone"
        )
        Check.equal(
            NoteDrag.ids(from: NoteDrag.payload(for: a, selection: [b.id, c.id])),
            [a.id],
            "so does one dragged from outside the selection"
        )

        // Dragging one of several ticked rows brings them all, which is what
        // dragging one of a set of highlighted things means anywhere else.
        let carried = Set(NoteDrag.ids(from: NoteDrag.payload(for: a, selection: [a.id, c.id])))
        Check.equal(carried, Set([a.id, c.id]), "dragging a selected note carries the selection")

        Check.equal(NoteDrag.ids(from: "not a uuid"), [], "junk on the pasteboard drops nothing")
    }
}

/// Why the source editor writes `body` and not `blocks`.
func sourceModeTests() {
    Check.suite("Source mode keeps the text as typed") {
        // The block round-trip is a normaliser. That is the right thing when
        // you are editing blocks — the document is whatever the blocks say —
        // but it makes a source editor that rewrites your text as you leave it.
        // Each of these is a rewrite `commitSource` must not perform.
        let normalised = [
            ("1) first\n2) second", "a `1)` list is rewritten to `1.`"),
            ("5. fifth", "a numbered item is renumbered from 1"),
            ("|a|b|\n|---|---|\n|1|2|", "a compact table gains padding"),
            ("-----", "a long divider is shortened to three dashes"),
        ]

        for (body, why) in normalised {
            var note = Note(body: body)
            // Exactly what a block-mode commit does (`commit(_:)`).
            note.blocks = note.blocks
            Check.expect(note.body != body, "block round-trip rewrites it — \(why)")
        }

        // What source mode does instead: the text reaches the file unchanged,
        // and still parses back to the same blocks, so switching modes is not
        // a one-way door.
        for (body, _) in normalised {
            let typed = Note(body: body)
            Check.equal(typed.body, body, "source mode stores the text verbatim")
            Check.equal(
                Markdown.serialize(Markdown.parse(body)),
                Markdown.serialize(Markdown.parse(Markdown.serialize(Markdown.parse(body)))),
                "and it still parses — normalising it twice changes nothing more"
            )
        }

        // Blank lines are structure in markdown, and a source editor that ate
        // them would reflow the document behind your back.
        let spaced = "# Title\n\n\nBody after two blank lines\n"
        Check.equal(
            Markdown.serialize(Markdown.parse(spaced)),
            spaced,
            "blank lines survive the parser untouched"
        )
    }
}
