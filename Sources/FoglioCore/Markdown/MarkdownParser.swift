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
        blocks.flatMap(lines(for:)).joined(separator: "\n")
    }

    private static func lines(for block: Block) -> [String] {
        switch block {
        case .h1(let t): return ["# " + t]
        case .h2(let t): return ["## " + t]
        case .paragraph(let t): return [t]
        case .listItem(let t): return ["- " + t]
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
    static func editableText(for block: Block) -> String {
        switch block {
        case .h1(let t): return "# " + t
        case .h2(let t): return "## " + t
        case .listItem(let t): return "- " + t
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
