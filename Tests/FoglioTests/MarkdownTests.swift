@testable import FoglioCore

func markdownTests() {
    Check.suite("Markdown — single blocks") {
        roundTrip(.h1("Reconcile, don't RPC"), "# Reconcile, don't RPC")
        roundTrip(.h2("What actually runs"), "## What actually runs")
        roundTrip(.paragraph("The controller's job is to make the world match."), "The controller's job is to make the world match.")
        roundTrip(.listItem("one thing"), "- one thing")
        roundTrip(.todo(text: "Write the finalizer path", checked: false), "- [ ] Write the finalizer path")
        roundTrip(.todo(text: "Re-read informer internals", checked: true), "- [x] Re-read informer internals")
        roundTrip(.divider, "---")
        roundTrip(.image(alt: "controller-runtime diagram", path: ""), "![controller-runtime diagram]()")
    }

    Check.suite("Markdown — the design's two lossy cases") {
        // Gap #2a: the design's raw() dropped the fence and the language, so a
        // code block could not be re-parsed. It survives now.
        let code = Block.code(
            language: "go",
            text: "func (r *Reconciler) Reconcile(ctx context.Context) error {\n\treturn nil\n}"
        )
        let codeMd = Markdown.serialize([code])
        Check.equal(
            codeMd,
            "```go\nfunc (r *Reconciler) Reconcile(ctx context.Context) error {\n\treturn nil\n}\n```",
            "code block keeps its fence and language"
        )
        Check.equal(Markdown.parse(codeMd), [code], "code block re-parses identically")

        // Gap #2b: tables were bare pipe rows with no header separator.
        let table = Block.table(rows: [
            ["Event", "Requeue", "Why"],
            ["Spec change", "immediate", "user is waiting"],
            ["Status drift", "30s", "cheap to re-check"],
        ])
        let tableMd = Markdown.serialize([table])
        Check.equal(
            tableMd,
            "| Event | Requeue | Why |\n| --- | --- | --- |\n| Spec change | immediate | user is waiting |\n| Status drift | 30s | cheap to re-check |",
            "table emits a GFM header separator"
        )
        Check.equal(Markdown.parse(tableMd), [table], "table re-parses identically")
    }

    Check.suite("Markdown — whole note round-trip") {
        // The verification step from the plan: every block type, serialize ->
        // parse -> serialize, byte-identical.
        let note: [Block] = [
            .h1("Reconcile, don't RPC"),
            .paragraph("Every handler is idempotent. See [[Go worker pool]] for the queue side."),
            .h2("What actually runs"),
            .code(language: "go", text: "jobs := make(chan Job)\nfor i := 0; i < n; i++ {\n\tgo work()\n}"),
            .todo(text: "Re-read informer / workqueue internals", checked: true),
            .todo(text: "Write the finalizer path", checked: false),
            .listItem("a plain bullet"),
            .table(rows: [["Event", "Requeue"], ["Spec change", "immediate"]]),
            .image(alt: "controller-runtime diagram", path: ""),
            .divider,
            .paragraph(""),
            .paragraph("Question for Arun: do we own the CRD versioning?"),
        ]

        let once = Markdown.serialize(note)
        let reparsed = Markdown.parse(once)
        let twice = Markdown.serialize(reparsed)

        Check.equal(reparsed, note, "every block survives the round-trip")
        Check.equal(twice, once, "serialize is byte-identical on the second pass")
    }

    Check.suite("Markdown — editing a block") {
        Check.equal(
            Markdown.applyEdit("## Promoted to a heading", to: .paragraph("was a paragraph")),
            .h2("Promoted to a heading"),
            "typing '## ' converts a paragraph to a heading"
        )
        Check.equal(
            Markdown.applyEdit("- [ ] now a todo", to: .paragraph("was a paragraph")),
            .todo(text: "now a todo", checked: false),
            "typing '- [ ] ' converts to a todo"
        )
        // Code keeps its type instead of re-deriving it, so typing '# ' inside a
        // code block stays code (the design's `prev` guard, :740).
        Check.equal(
            Markdown.applyEdit("# not a heading", to: .code(language: "go", text: "old")),
            .code(language: "go", text: "# not a heading"),
            "editing inside a code block does not re-type it"
        )
    }

    Check.suite("Go tokenizer") {
        let tokens = GoSyntax.tokenize("func main() { // go")
        Check.equal(tokens.first, Token(text: "func", role: .keyword), "func is a keyword")
        Check.expect(
            tokens.contains(Token(text: "main", role: .identifier)),
            "main is an identifier"
        )
        Check.expect(
            tokens.contains { $0.role == .comment && $0.text == "// go" },
            "trailing // comment is one token, not re-tokenized as a keyword"
        )
        Check.equal(
            GoSyntax.tokenize(#"s := "hello""#).last,
            Token(text: #""hello""#, role: .string),
            "a quoted string is one token"
        )
        Check.equal(GoSyntax.tokenize("").count, 1, "empty line still yields one token for height")
    }

    Check.suite("Wiki links") {
        Check.equal(
            WikiLink.spans(in: "See [[Go worker pool]] for the queue side."),
            [.text("See "), .link("Go worker pool"), .text(" for the queue side.")],
            "a link splits into three spans"
        )
        Check.equal(
            WikiLink.spans(in: "no links here"),
            [.text("no links here")],
            "plain text is a single span"
        )
        Check.equal(
            WikiLink.spans(in: "unterminated [[link"),
            [.text("unterminated [[link")],
            "an unterminated link stays plain text"
        )
        Check.equal(
            WikiLink.resolve("worker", in: ["Scratchpad", "Go worker pool"]),
            "Go worker pool",
            "links resolve by case-insensitive substring"
        )
    }
}

private func roundTrip(_ block: Block, _ expected: String, line: UInt = #line) {
    let text = Markdown.serialize([block])
    Check.equal(text, expected, "serialize \(expected)", line: line)
    Check.equal(Markdown.parse(text), [block], "parse back \(expected)", line: line)
}
