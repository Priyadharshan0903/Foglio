import Foundation
import Observation

/// The whole data layer.
///
/// Everything lives in memory and is written through to disk under
/// Application Support:
///
///     Foglio/
///       notes/<slug>-<id8>.md    one markdown file per note
///       tasks.json
///       log.json
///       milestones.json
///
/// Notes are the format users are meant to see; the three JSON files are small
/// enough that rewriting one on change costs nothing at this scale.
@Observable
@MainActor
final class Store {
    private(set) var notes: [Note] = []
    private(set) var tasks: [TaskItem] = []
    private(set) var log: [LogEntry] = []
    private(set) var milestones: [Milestone] = []

    let root: URL
    private var loaded = false

    /// The filename each note currently occupies on disk.
    ///
    /// Filenames are derived from the title, so they change as you rename a
    /// note. Without remembering the previous name, every save wrote a *new*
    /// file and orphaned the last one — typing an 11-character title left 11
    /// files behind, which then reloaded as 11 duplicate notes.
    private var fileNames: [UUID: String] = [:]

    /// Pending debounced disk writes, keyed by note.
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]

    init(root: URL? = nil) {
        self.root = root ?? Store.defaultRoot()
    }

    static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Foglio", isDirectory: true)
    }

    private var notesDir: URL { root.appendingPathComponent("notes", isDirectory: true) }
    private var tasksURL: URL { root.appendingPathComponent("tasks.json") }
    private var logURL: URL { root.appendingPathComponent("log.json") }
    private var milestonesURL: URL { root.appendingPathComponent("milestones.json") }

    // MARK: - Loading

    func load() {
        guard !loaded else { return }
        loaded = true

        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        notes = loadNotes()

        tasks = decode([TaskItem].self, from: tasksURL) ?? []
        log = decode([LogEntry].self, from: logURL) ?? []
        milestones = decode([Milestone].self, from: milestonesURL) ?? []

        if milestones.isEmpty { milestones = Seed.milestones }
        if notes.isEmpty && tasks.isEmpty && log.isEmpty {
            notes = Seed.notes
            tasks = Seed.tasks
            log = Seed.log
            saveNotes()
            saveTasks()
            saveLog()
        }
        saveMilestones()
    }

    /// Reads every note file, collapsing duplicate ids left behind by the
    /// filename-churn bug above and deleting the stale files as it goes, so an
    /// affected store heals itself on next launch.
    private func loadNotes() -> [Note] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" } ?? []

        var byId: [UUID: Note] = [:]
        var names: [UUID: String] = [:]

        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let note = NoteFile.decode(text)

            if let existing = byId[note.id] {
                // Same note, two files. Keep whichever was written last.
                let keepNew = note.updatedAt > existing.updatedAt
                let loserName = keepNew ? names[note.id] : url.lastPathComponent
                if let loserName {
                    try? FileManager.default.removeItem(at: notesDir.appendingPathComponent(loserName))
                }
                if keepNew {
                    byId[note.id] = note
                    names[note.id] = url.lastPathComponent
                }
            } else {
                byId[note.id] = note
                names[note.id] = url.lastPathComponent
            }
        }

        fileNames = names
        return byId.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? e.encode(value) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Notes

    func note(id: UUID) -> Note? { notes.first { $0.id == id } }

    /// The bar's always-there quick-notes note — found by `id` and created
    /// once if it doesn't exist yet, unlike the rest of Notes where every note
    /// starts as a fresh untitled file.
    @discardableResult
    func quickNote(id: UUID) -> Note {
        if let existing = note(id: id) { return existing }
        let note = Note(id: id, title: "Quick notes", folder: .scratch)
        upsert(note)
        return note
    }

    /// `debounced` keeps the in-memory value current immediately but delays the
    /// disk write. Use it while typing: writing a whole file per keystroke is
    /// both slow and what produced the orphaned-file bug.
    func upsert(_ note: Note, debounced: Bool = false) {
        var updated = note
        updated.updatedAt = Clock.now()
        if let i = notes.firstIndex(where: { $0.id == note.id }) {
            notes[i] = updated
        } else {
            notes.insert(updated, at: 0)
        }
        if debounced { scheduleSave(updated) } else { saveNote(updated) }
    }

    private func scheduleSave(_ note: Note) {
        pendingSaves[note.id]?.cancel()
        pendingSaves[note.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.saveNote(note)
            self.pendingSaves[note.id] = nil
        }
    }

    /// Force out anything still queued — call when a note stops being edited.
    func flushPendingSaves() {
        for (id, task) in pendingSaves {
            task.cancel()
            if let note = notes.first(where: { $0.id == id }) { saveNote(note) }
        }
        pendingSaves.removeAll()
    }

    @discardableResult
    func newNote(in folder: Folder) -> Note {
        let note = Note(title: "", body: "", folder: folder)
        notes.insert(note, at: 0)
        saveNote(note)
        return note
    }

    func deleteNote(id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: i)
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        if let name = fileNames.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: notesDir.appendingPathComponent(name))
        }
    }

    private func saveNote(_ note: Note) {
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let name = NoteFile.filename(for: note)
        // A retitled note moves file: drop the old one rather than orphan it.
        if let previous = fileNames[note.id], previous != name {
            try? FileManager.default.removeItem(at: notesDir.appendingPathComponent(previous))
        }
        fileNames[note.id] = name

        try? NoteFile.encode(note).write(
            to: notesDir.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    private func saveNotes() { notes.forEach(saveNote) }

    // MARK: - Tasks

    func addTask(_ task: TaskItem) {
        tasks.append(task)
        saveTasks()
    }

    func update(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i] = task
        saveTasks()
    }

    func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        saveTasks()
    }

    func move(taskId: UUID, to lane: Lane) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[i].lane = lane
        if lane == .delegate && tasks[i].meta.isEmpty { tasks[i].meta = "Follow up" }
        saveTasks()
    }

    /// Completing a task optionally writes it into today's log (:811).
    func setDone(taskId: UUID, done: Bool, autoLog: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[i].done = done
        tasks[i].completedAt = done ? Clock.now() : nil
        saveTasks()
        if done && autoLog {
            addLog(LogEntry(text: tasks[i].label, kind: .task))
        }
    }

    /// A todo block reads as "in tasks" when a task with the same label exists.
    /// Derived rather than stored — see the note on `Block`.
    func hasTask(labelled label: String) -> Bool {
        tasks.contains { $0.label == label }
    }

    private func saveTasks() { write(tasks, to: tasksURL) }

    // MARK: - Log

    func addLog(_ entry: LogEntry) {
        log.append(entry)
        saveLog()
    }

    var todaysLog: [LogEntry] {
        let cal = Calendar.current
        return log.filter { cal.isDateInToday($0.at) }
    }

    private func saveLog() { write(log, to: logURL) }

    // MARK: - Milestones

    func toggleStep(milestoneId: UUID, stepId: UUID) {
        guard let m = milestones.firstIndex(where: { $0.id == milestoneId }),
              let s = milestones[m].steps.firstIndex(where: { $0.id == stepId })
        else { return }
        milestones[m].steps[s].done.toggle()
        saveMilestones()
    }

    private func saveMilestones() { write(milestones, to: milestonesURL) }

    /// Pin targets: every incomplete task, then every milestone (:907).
    var pinTargets: [String] {
        tasks.filter { !$0.done }.map(\.label) + milestones.map(\.title)
    }

    // MARK: - Import

    /// Replaces everything with an imported archive. Note files that are no
    /// longer represented are removed, so importing into a populated store
    /// leaves it matching the archive rather than merged with it.
    func replaceAll(with archive: Archive) {
        if let existing = try? FileManager.default.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil) {
            for url in existing where url.pathExtension == "md" {
                try? FileManager.default.removeItem(at: url)
            }
        }

        notes = archive.notes
        tasks = archive.tasks
        log = archive.log
        milestones = archive.milestones

        saveNotes()
        saveTasks()
        saveLog()
        saveMilestones()
    }
}
