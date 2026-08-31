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

        notes = (try? FileManager.default.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map(NoteFile.decode)
            .sorted { $0.updatedAt > $1.updatedAt } ?? []

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

    func upsert(_ note: Note) {
        var updated = note
        updated.updatedAt = Date()
        if let i = notes.firstIndex(where: { $0.id == note.id }) {
            notes[i] = updated
        } else {
            notes.insert(updated, at: 0)
        }
        saveNote(updated)
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
        let note = notes.remove(at: i)
        try? FileManager.default.removeItem(at: notesDir.appendingPathComponent(NoteFile.filename(for: note)))
    }

    private func saveNote(_ note: Note) {
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let url = notesDir.appendingPathComponent(NoteFile.filename(for: note))
        try? NoteFile.encode(note).write(to: url, atomically: true, encoding: .utf8)
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
        tasks[i].completedAt = done ? Date() : nil
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
}
