import Foundation

// Plain value types, not SwiftData models.
//
// SwiftData is unavailable here: the Command Line Tools SDK ships neither the
// `SwiftData` module nor its `SwiftDataMacros` plugin, so `@Model` cannot
// compile without Xcode. That turns out to suit this app — the dataset is one
// person's notes and tasks, and the chosen requirement was local storage with
// plain-text export. Notes are therefore `.md` files on disk with YAML
// frontmatter, and export is largely "the store already is the export".

enum Folder: String, CaseIterable, Identifiable, Codable {
    case platform, career, scratch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .platform: "Platform"
        case .career: "Career"
        case .scratch: "Scratch"
        }
    }
}

enum Lane: String, CaseIterable, Identifiable, Codable {
    case priority, ordinary, delegate

    var id: String { rawValue }

    /// `laneName` (Day Log.dc.html:801).
    var label: String {
        switch self {
        case .priority: "Priority"
        case .ordinary: "Ordinary"
        case .delegate: "Delegate"
        }
    }

    var emptyText: String {
        switch self {
        case .priority: "Nothing urgent."
        case .ordinary: "Nothing queued."
        case .delegate: "No follow ups."
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
    var updatedAt: Date = Date()

    var blocks: [Block] {
        get { Markdown.parse(body) }
        set { body = Markdown.serialize(newValue) }
    }

    /// First non-empty paragraph or todo, link brackets stripped (:1022).
    var snippet: String {
        let text = blocks.first {
            if case .paragraph(let t) = $0 { return !t.isEmpty }
            return $0.isTodo
        }?.plainText ?? ""
        return text.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return (title + " " + body).lowercased().contains(query.lowercased())
    }
}

struct TaskItem: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var label: String = ""
    var lane: Lane = .priority
    var meta: String = ""
    var done: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
}

struct LogEntry: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var at: Date = Date()
    var text: String = ""
    var kind: LogKind = .manual

    init(text: String, kind: LogKind, at: Date = Date(), id: UUID = UUID()) {
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
