import Foundation

// Plain value types, not SwiftData models.
//
// SwiftData is unavailable here: the Command Line Tools SDK ships neither the
// `SwiftData` module nor its `SwiftDataMacros` plugin, so `@Model` cannot
// compile without Xcode. That turns out to suit this app — the dataset is one
// person's notes and tasks, and the chosen requirement was local storage with
// plain-text export. Notes are therefore `.md` files on disk with YAML
// frontmatter, and export is largely "the store already is the export".

/// A note's folder — a name, not a fixed set of cases.
///
/// Folders are the user's to make: the three the app ships with are only what a
/// new install is seeded with. The raw value is what lands in the file's
/// frontmatter, so a folder created in the app stays legible to anything else
/// reading the markdown directory.
///
/// Identity is case-insensitive — someone who types "reading" today and
/// "Reading" tomorrow means one folder, not two — while the raw value keeps
/// whatever capitalisation it was made with. Files written before folders were
/// user-made carry lowercase names (`folder: platform`), which is why `label`
/// capitalises for display instead of trusting the stored case.
struct Folder: RawRepresentable, Codable, Hashable, Identifiable {
    let rawValue: String

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Every note belongs somewhere. An empty name would be a folder you
        // could neither see in the list nor click your way out of.
        self.rawValue = trimmed.isEmpty ? "Scratch" : trimmed
    }

    init(_ name: String) { self.init(rawValue: name) }

    var id: String { rawValue.lowercased() }

    var label: String { rawValue.prefix(1).uppercased() + String(rawValue.dropFirst()) }

    static func == (lhs: Folder, rhs: Folder) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // Encoded as the bare string, so `folders.json` and the export archive read
    // the same as the frontmatter does.
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let platform = Folder("Platform")
    static let career = Folder("Career")
    static let scratch = Folder("Scratch")

    /// The three the design draws in the folder pane, and what a new install
    /// starts with.
    static let starters: [Folder] = [.platform, .career, .scratch]
}

/// A task's lane — its status column on the board, and a name rather than a
/// fixed set of cases.
///
/// The same reasoning as `Folder`: "Priority / Ordinary / Delegate" is one
/// person's way of splitting work, so the three the app ships with are what a
/// new install is *seeded* with, not the only statuses there can be. The board
/// shows `Store.lanes` in the order it holds them, which is what makes the
/// columns reorderable — a lane's position is a property of the list, not of
/// the lane.
///
/// Identity is case-insensitive — "blocked" today and "Blocked" tomorrow mean
/// one column, not two — while the raw value keeps whatever capitalisation it
/// was made with. `tasks.json` written before lanes were user-made stores the
/// old lowercase raw values (`lane: priority`), which is why `label`
/// capitalises for display instead of trusting the stored case.
struct Lane: RawRepresentable, Codable, Hashable, Identifiable {
    let rawValue: String

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Every task is in some column. An empty name would be a lane you could
        // neither see on the board nor drag a row out of.
        self.rawValue = trimmed.isEmpty ? "Priority" : trimmed
    }

    init(_ name: String) { self.init(rawValue: name) }

    var id: String { rawValue.lowercased() }

    var label: String { rawValue.prefix(1).uppercased() + String(rawValue.dropFirst()) }

    static func == (lhs: Lane, rhs: Lane) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // Encoded as the bare string, so a lane reads the same in `lanes.json`, in
    // `tasks.json` and in the export archive — and so tasks written by the
    // enum version of this type still decode.
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let priority = Lane("Priority")
    static let ordinary = Lane("Ordinary")
    static let delegate = Lane("Delegate")

    /// The three the design draws on the board, and what a new install starts
    /// with (`laneName`, Day Log.dc.html:801).
    static let starters: [Lane] = [.priority, .ordinary, .delegate]

    /// Placeholder for a column with nothing in it.
    ///
    /// The shipped three keep the copy the design wrote for them; a lane
    /// someone made themselves gets a neutral line, since the app has no idea
    /// what "Blocked" or "This week" is supposed to feel like when it's empty.
    var emptyText: String {
        switch id {
        case Lane.priority.id: "Nothing urgent."
        case Lane.ordinary.id: "Nothing queued."
        case Lane.delegate.id: "No follow ups."
        default: "Nothing here."
        }
    }
}

enum LogKind: String, Codable {
    case task, focus, manual
}

struct Note: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var title: String = ""
    /// Markdown is the source of truth — see `Markdown`.
    var body: String = ""
    var folder: Folder = .scratch
    /// A task label or milestone title this note is pinned to (:1034).
    var pin: String?
    var updatedAt: Date = Clock.now()

    var blocks: [Block] {
        get { Markdown.parse(body) }
        set { body = Markdown.serialize(newValue) }
    }

    /// First non-empty paragraph or todo, link brackets stripped (:1022).
    ///
    /// Deliberately scans lines instead of going through `blocks`. The note list
    /// asks every note for its snippet on every render, so a full markdown parse
    /// here meant re-parsing the entire library on each keystroke — which is
    /// exactly what made typing stutter.
    var snippet: String {
        var insideFence = false

        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") { insideFence.toggle(); continue }
            if insideFence || line.isEmpty { continue }

            // Todo: "- [ ] text" / "- [x] text"
            if line.hasPrefix("- ["), let close = line.firstIndex(of: "]"),
               line.index(after: close) < line.endIndex {
                return strip(String(line[line.index(close, offsetBy: 2)...]))
            }
            // Headings, bullets, tables, dividers and images aren't snippets.
            if line.hasPrefix("#") || line.hasPrefix("- ") || line.hasPrefix("|")
                || line.hasPrefix("---") || line.hasPrefix("![") { continue }
            // Nor are numbered items — "1. First step" reads as a list, not as
            // a description of the note.
            if isNumberedItem(line) { continue }

            return strip(String(line))
        }
        return ""
    }

    /// `1. text`, matched on the raw line — kept in step with
    /// `Markdown.parseOrdered`, but without parsing the note to find out.
    private func isNumberedItem(_ line: Substring) -> Bool {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return false }
        let rest = line.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    private func strip(_ text: String) -> String {
        text.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
    }

    /// Case-insensitive without lowercasing (and so reallocating) the whole body
    /// for every note on every keystroke.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return title.range(of: query, options: .caseInsensitive) != nil
            || body.range(of: query, options: .caseInsensitive) != nil
    }
}

struct TaskItem: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var label: String = ""
    var lane: Lane = .priority
    var meta: String = ""
    var done: Bool = false
    var completedAt: Date?
    var createdAt: Date = Clock.now()
}

struct LogEntry: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var at: Date = Clock.now()
    var text: String = ""
    var kind: LogKind = .manual

    init(text: String, kind: LogKind, at: Date = Clock.now(), id: UUID = UUID()) {
        self.id = id
        self.at = at
        self.text = text
        self.kind = kind
    }
}

struct MilestoneStep: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var label: String = ""
    var done: Bool = false
}

struct Milestone: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var title: String = ""
    var when: String = ""
    var goal: String = ""
    var steps: [MilestoneStep] = []
}
