import Foundation

/// Everything, in one Codable box — the lossless half of an export.
struct Archive: Codable, Equatable {
    var notes: [Note] = []
    /// Trashed notes, with their `deletedAt` stamps, so importing an archive
    /// restores the trash and its countdowns rather than quietly dropping
    /// notes that were still recoverable. Optional like the rest — archives
    /// written before there was a trash don't have the key.
    var trash: [Note]?
    /// Optional because archives written before folders were user-made don't
    /// have the key — and a folder list can be rebuilt from the notes, so its
    /// absence costs only the empty folders.
    var folders: [Folder]?
    /// Optional for the same reason `folders` is — archives written before
    /// lanes were user-made carry only the lane named on each task.
    var lanes: [Lane]?
    var tasks: [TaskItem] = []
    var taskWorkspace: TaskWorkspace?
    var attachments: [String: Data]?
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
            trash: store.trash,
            folders: store.folders,
            lanes: store.lanes,
            tasks: store.manuallyOrderedTasks,
            taskWorkspace: store.taskWorkspace,
            attachments: LibraryAttachments.snapshot(at: store.root),
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
        if let attachments = archive.attachments { try LibraryAttachments.restore(attachments, at: root) }

        for note in archive.notes {
            var readable = note
            readable.body = readable.body.replacingOccurrences(of: "(attachments/", with: "(../attachments/")
            try NoteFile.encode(readable).write(
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

        try tasksMarkdown(archive.tasks, lanes: archive.lanes, statuses: archive.taskWorkspace?.statuses).write(
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

    /// The lanes named by `tasks`, each once, in the order they first appear.
    private static func laneOrder(in tasks: [TaskItem]) -> [Lane] {
        var seen = Set<String>()
        return tasks.map(\.lane).filter { seen.insert($0.id).inserted }
    }

    /// `lanes` is the board's column order, so the export reads top-to-bottom
    /// the way the board reads left-to-right. Passing none — an archive from
    /// before lanes were user-made, or a caller that only has tasks — falls
    /// back to the order the lanes first appear in the tasks themselves.
    static func tasksMarkdown(_ tasks: [TaskItem], lanes: [Lane]? = nil, statuses: [TaskBoardStatus]? = nil) -> String {
        var out = ["# Tasks", ""]
        func properties(_ task: TaskItem) -> [String] {
            var fields: [String] = []
            if task.taskPriority != .none { fields.append("Priority: " + task.taskPriority.label) }
            if let project = task.project { fields.append("Project: " + project) }
            if let assignee = task.assignee { fields.append("Assignee: " + assignee) }
            if !(task.labels ?? []).isEmpty { fields.append("Labels: " + (task.labels ?? []).joined(separator: ", ")) }
            if let due = task.dueDate { fields.append("Due: " + due.formatted(date: .abbreviated, time: .omitted)) }
            if let estimate = task.estimate { fields.append("Estimate: \(estimate) points") }
            func reference(_ id: UUID) -> String { tasks.first { $0.id == id }.map { $0.ticketID.isEmpty ? id.uuidString : $0.ticketID } ?? id.uuidString }
            if let parent = task.parentID { fields.append("Parent: " + reference(parent)) }
            if !(task.blockedBy ?? []).isEmpty { fields.append("Blocked by: " + (task.blockedBy ?? []).map(reference).joined(separator: ", ")) }
            return fields.map { "  - " + $0 }
        }

        for lane in lanes ?? laneOrder(in: tasks) {
            let open = tasks.filter { $0.lane == lane && !$0.done }
            guard !open.isEmpty else { continue }
            out.append("## \(lane.label)")
            for task in open {
                let rich = task.meta.contains("\n") || task.meta.range(of: #"[*_\x60\[\]|]|^>"#, options: .regularExpression) != nil
                let meta = task.meta.isEmpty || rich ? "" : " — _\(task.meta)_"
                let statusName = statuses?.first { $0.id == task.statusID }?.name ?? task.workflowStatus.label
                let status = task.statusID != nil || [.backlog, .inProgress].contains(task.workflowStatus) ? " _(\(statusName))_" : ""
                out.append("- [ ] \(task.ticketID.isEmpty ? "" : task.ticketID + " ")\(task.label)\(status)\(meta)")
                out += properties(task)
                if rich { out += task.meta.components(separatedBy: "\n").map { "  " + $0 } }
            }
            out.append("")
        }

        let done = tasks.filter(\.done)
        if !done.isEmpty {
            out.append("## Done")
            for task in done {
                let at = task.completedAt.map { " `\(Clock.hhmm($0))`" } ?? ""
                out.append("- [x] \(task.ticketID.isEmpty ? "" : task.ticketID + " ")\(task.label)\(at)")
                out += properties(task)
                if !task.meta.isEmpty { out += task.meta.components(separatedBy: "\n").map { "  " + $0 } }
            }
            out.append("")
        }

        return out.joined(separator: "\n")
    }
}
