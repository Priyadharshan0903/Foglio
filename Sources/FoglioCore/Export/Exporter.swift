import Foundation

/// Everything, in one Codable box — the lossless half of an export.
struct Archive: Codable, Equatable {
    var notes: [Note] = []
    var tasks: [TaskItem] = []
    var log: [LogEntry] = []
    var milestones: [Milestone] = []
}

/// Writes a self-contained folder you can hand to anything.
///
/// Notes are already markdown in the live store, so this is less about
/// converting and more about gathering: the readable files for a human, plus one
/// `foglio-archive.json` that can be re-imported without losing ids or
/// timestamps.
///
///     Foglio Export 2026-08-31/
///       notes/<slug>-<id8>.md
///       log/2026-08-31.md
///       tasks.md
///       foglio-archive.json
enum Exporter {
    @MainActor
    static func archive(from store: Store) -> Archive {
        Archive(
            notes: store.notes,
            tasks: store.tasks,
            log: store.log,
            milestones: store.milestones
        )
    }

    @discardableResult
    static func export(_ archive: Archive, to parent: URL, dated date: Date = Date()) throws -> URL {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        let root = parent.appendingPathComponent("Foglio Export \(stamp.string(from: date))", isDirectory: true)

        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("log"), withIntermediateDirectories: true)

        for note in archive.notes {
            try NoteFile.encode(note).write(
                to: root.appendingPathComponent("notes/\(NoteFile.filename(for: note))"),
                atomically: true,
                encoding: .utf8
            )
        }

        for (day, entries) in groupByDay(archive.log) {
            try logMarkdown(day: day, entries: entries).write(
                to: root.appendingPathComponent("log/\(day).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        try tasksMarkdown(archive.tasks).write(
            to: root.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: root.appendingPathComponent("foglio-archive.json"))

        return root
    }

    static func importArchive(from url: URL) throws -> Archive {
        // Accept either the archive file itself or the folder containing it.
        var file = url
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            file = url.appendingPathComponent("foglio-archive.json")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Archive.self, from: Data(contentsOf: file))
    }

    // MARK: - Markdown renderings

    static func groupByDay(_ entries: [LogEntry]) -> [(String, [LogEntry])] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let grouped = Dictionary(grouping: entries) { f.string(from: $0.at) }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted { $0.at < $1.at }) }
    }

    static func logMarkdown(day: String, entries: [LogEntry]) -> String {
        var out = ["# \(day)", ""]
        for entry in entries {
            out.append("- `\(Clock.hhmm(entry.at))` \(entry.text) _(\(entry.kind.rawValue))_")
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func tasksMarkdown(_ tasks: [TaskItem]) -> String {
        var out = ["# Tasks", ""]

        for lane in Lane.allCases {
            let open = tasks.filter { $0.lane == lane && !$0.done }
            guard !open.isEmpty else { continue }
            out.append("## \(lane.label)")
            for task in open {
                let meta = task.meta.isEmpty ? "" : " — _\(task.meta)_"
                out.append("- [ ] \(task.label)\(meta)")
            }
            out.append("")
        }

        let done = tasks.filter(\.done)
        if !done.isEmpty {
            out.append("## Done")
            for task in done {
                let at = task.completedAt.map { " `\(Clock.hhmm($0))`" } ?? ""
                out.append("- [x] \(task.label)\(at)")
            }
            out.append("")
        }

        return out.joined(separator: "\n")
    }
}
