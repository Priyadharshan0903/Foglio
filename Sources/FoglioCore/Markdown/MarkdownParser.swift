import Foundation

/// Markdown is the source of truth for a note's body: a note *is* a `.md` file,
/// which is what makes plain-text export nearly free.
///
/// Two things the design got wrong are fixed here (see plan, gap #2). Its
/// `raw()` (Day Log.dc.html:731) returned code and table blocks verbatim, so a
/// code block lost its fence and language and a table was bare pipe rows with no
/// header separator — neither could be re-parsed. `serialize`/`parse` below emit
/// real fenced blocks and GFM tables, and round-trip exactly.
enum Markdown {

    // MARK: - Whole document

    static func serialize(_ blocks: [Block]) -> String {
        let numbers = ordinals(of: blocks)
        return zip(blocks, numbers)
            .flatMap { lines(for: $0, ordinal: $1) }
            .joined(separator: "\n")
    }

    /// The number each block carries as a numbered-list item, or nil when it
    /// isn't one. A run restarts at 1 after any other kind of block, so two
    /// lists separated by a paragraph don't share a counter.
    ///
    /// This is the single definition of the numbering, used both to write the
    /// file and to draw the list, so the two can't drift apart.
    static func ordinals(of blocks: [Block]) -> [Int?] {
        var numbers: [Int?] = []
        var n = 0
        for block in blocks {
            if case .orderedItem = block {
                n += 1
                numbers.append(n)
            } else {
                n = 0
                numbers.append(nil)
            }
        }
        return numbers
    }

    private static func lines(for block: Block, ordinal: Int?) -> [String] {
        switch block {
        case .h1(let t): return ["# " + t]
        case .h2(let t): return ["## " + t]
        case .paragraph(let t): return [t]
        case .listItem(let t): return ["- " + t]
        case .orderedItem(let t): return ["\(ordinal ?? 1). " + t]
        case .todo(let t, let checked): return ["- [" + (checked ? "x" : " ") + "] " + t]
        case .divider: return ["---"]
        case .image(let alt, let path): return ["![\(alt)](\(path))"]

        case .code(let language, let text):
            return ["```" + language] + text.components(separatedBy: "\n") + ["```"]

        case .table(let rows):
            guard let header = rows.first else { return [] }
            var out = [row(header)]
            out.append(row(Array(repeating: "---", count: header.count)))
            out.append(contentsOf: rows.dropFirst().map(row))
            return out
        }
    }

    private static func row(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let all = text.components(separatedBy: "\n")
        var i = 0

        while i < all.count {
            let line = all[i]

            // Fenced code: consume through the closing fence.
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < all.count, !all[i].hasPrefix("```") {
                    body.append(all[i])
                    i += 1
                }
                i += 1 // step past the closing fence (or off the end if unterminated)
                blocks.append(.code(language: language, text: body.joined(separator: "\n")))
                continue
            }

            // GFM table: consume the run of pipe rows, dropping the separator.
            if isTableRow(line) {
                var rows: [[String]] = []
                while i < all.count, isTableRow(all[i]) {
                    if !isSeparatorRow(all[i]) { rows.append(cells(all[i])) }
                    i += 1
                }
                blocks.append(.table(rows: rows))
                continue
            }

            blocks.append(parseLine(line))
            i += 1
        }

        return blocks
    }

    // MARK: - Single line

    /// Port of `parseRaw` (:739), minus the code/table cases which `parse`
    /// handles because they span lines.
    private static func parseLine(_ raw: String) -> Block {
        if raw.hasPrefix("## ") { return .h2(String(raw.dropFirst(3))) }
        if raw.hasPrefix("# ") { return .h1(String(raw.dropFirst(2))) }
        if let todo = parseTodo(raw) { return todo }
        if raw.hasPrefix("- ") { return .listItem(String(raw.dropFirst(2))) }
        if let ordered = parseOrdered(raw) { return ordered }
        if raw.hasPrefix("---") { return .divider }
        if let image = parseImage(raw) { return image }
        return .paragraph(raw)
    }

    private static func parseTodo(_ raw: String) -> Block? {
        // `- [ ] text` / `- [x] text`, case-insensitive on the mark (:743).
        guard raw.count >= 6, raw.hasPrefix("- [") else { return nil }
        let mark = raw[raw.index(raw.startIndex, offsetBy: 3)]
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        let after = raw.index(raw.startIndex, offsetBy: 4)
        guard raw[after] == "]" else { return nil }
        let rest = raw.index(after, offsetBy: 1)
        guard raw[rest] == " " else { return nil }
        return .todo(
            text: String(raw[raw.index(rest, offsetBy: 1)...]),
            checked: mark != " "
        )
    }

    /// `1. text` or `1) text`, the two markers CommonMark allows. Whatever
    /// number is written is discarded — position decides it — and the digit run
    /// is capped at 9 like CommonMark, so "1234567890. " stays a paragraph.
    private static func parseOrdered(_ raw: String) -> Block? {
        let digits = raw.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = raw.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return .orderedItem(String(rest.dropFirst(2)))
    }

    private static func parseImage(_ raw: String) -> Block? {
        guard raw.hasPrefix("!["), raw.hasSuffix(")"),
              let close = raw.firstIndex(of: "]"),
              raw.index(after: close) < raw.endIndex,
              raw[raw.index(after: close)] == "("
        else { return nil }
        let alt = String(raw[raw.index(raw.startIndex, offsetBy: 2)..<close])
        let pathStart = raw.index(close, offsetBy: 2)
        let path = String(raw[pathStart..<raw.index(before: raw.endIndex)])
        return .image(alt: alt, path: path)
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        guard body.hasPrefix("|") else { return false }
        return body.allSatisfy { "|-: \t".contains($0) } && body.contains("-")
    }

    private static func cells(_ line: String) -> [String] {
        var body = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Per-block editing

    /// What a block looks like while you're editing it — port of `raw()` (:731).
    ///
    /// Code and table blocks show their inner text without the fence or the
    /// separator row, matching the design's editor. That's a display concern and
    /// stays lossy on purpose; `serialize` is the lossless path.
    /// `ordinal` only matters for a numbered item: it's what puts the item's
    /// real number in front of you while you edit it, rather than a fixed "1.".
    static func editableText(for block: Block, ordinal: Int? = nil) -> String {
        switch block {
        case .h1(let t): return "# " + t
        case .h2(let t): return "## " + t
        case .listItem(let t): return "- " + t
        case .orderedItem(let t): return "\(ordinal ?? 1). " + t
        case .todo(let t, let checked): return "- [" + (checked ? "x" : " ") + "] " + t
        case .paragraph(let t): return t
        case .code(_, let text): return text
        case .table(let rows): return rows.map { $0.joined(separator: "|") }
            .joined(separator: "\n")
        case .image(let alt, _): return alt
        case .divider: return "---"
        }
    }

    /// Re-parses a block after an edit. Code and table keep their type rather
    /// than re-deriving it from the text (:740).
    static func applyEdit(_ text: String, to previous: Block) -> Block {
        switch previous {
        case .code(let language, _):
            return .code(language: language, text: text)
        case .table:
            return .table(rows: text.components(separatedBy: "\n").map {
                $0.components(separatedBy: "|").map { c in
                    c.trimmingCharacters(in: .whitespaces)
                }
            })
        case .image(_, let path):
            return .image(alt: text, path: path)
        default:
            return parseLine(text)
        }
    }
}
