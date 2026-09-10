import Foundation
import Observation

/// The whole data layer.
///
/// Everything lives in memory and is written through to disk under
/// Application Support:
///
///     Foglio/
///       notes/<slug>-<id8>.md    one markdown file per note
///       trash/<slug>-<id8>.md    trashed notes, awaiting the ten-day purge
///       folders.json
///       lanes.json
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
    /// Notes moved to the trash, newest first.
    ///
    /// A separate list rather than a flag on `notes`, so that nothing which
    /// reads `notes` — search, the folder counts, pin targets, wiki-links,
    /// the export — has to learn about the trash to keep trashed notes out.
    private(set) var trash: [Note] = []
    /// Every folder the sidebar offers, in the order it shows them.
    ///
    /// Kept as its own list rather than derived from the notes, because a
    /// folder you have just made — and one you have emptied — has no notes to
    /// derive it from, and should still be there.
    private(set) var folders: [Folder] = []
    /// Every lane the task board shows, in the order it shows them.
    ///
    /// Its own list for the same reason `folders` is: a lane you have just
    /// made — and one you have emptied — has no tasks to be derived from, and
    /// the *order* of the columns exists nowhere else at all.
    private(set) var lanes: [Lane] = []
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

    /// The same, for the files under `trash/`.
    private var trashFileNames: [UUID: String] = [:]

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
    private var trashDir: URL { root.appendingPathComponent("trash", isDirectory: true) }
    private var foldersURL: URL { root.appendingPathComponent("folders.json") }
    private var lanesURL: URL { root.appendingPathComponent("lanes.json") }
    private var tasksURL: URL { root.appendingPathComponent("tasks.json") }
    private var logURL: URL { root.appendingPathComponent("log.json") }
    private var milestonesURL: URL { root.appendingPathComponent("milestones.json") }

    // MARK: - Loading

    func load() {
        guard !loaded else { return }
        loaded = true

        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        notes = loadNotes()
        trash = loadTrash()

        folders = decode([Folder].self, from: foldersURL) ?? Folder.starters
        lanes = decode([Lane].self, from: lanesURL) ?? Lane.starters
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
        reconcileFolders()
        reconcileLanes()
        saveMilestones()

        // Before anything can render. A note whose ten days ran out while the
        // app was closed should never be visible, however late the sweep is.
        purgeExpiredTrash()
    }

    /// Makes sure every folder a note claims is one the sidebar lists.
    ///
    /// Without this a note can sit somewhere unreachable: an import brings its
    /// own folders, and these are plain text files, so `folder:` can also be
    /// edited by hand. Scratch is always kept for the same reason — it is where
    /// a note with nowhere else to go ends up.
    private func reconcileFolders() {
        var seen = Set(folders.map(\.id))
        for note in notes where !seen.contains(note.folder.id) {
            folders.append(note.folder)
            seen.insert(note.folder.id)
        }
        if !seen.contains(Folder.scratch.id) { folders.append(.scratch) }
        saveFolders()
    }

    /// Makes sure every lane a task claims is a column on the board, and that
    /// there is at least one column to begin with.
    ///
    /// Same job as `reconcileFolders`, with one extra worry: `tasks.json` is
    /// hand-editable and an imported archive brings its own lanes, so a task
    /// can name a column that isn't there — and a task in no visible column is
    /// a task you can't reach. Lanes discovered this way join the end rather
    /// than displacing the order already chosen.
    private func reconcileLanes() {
        var seen = Set(lanes.map(\.id))
        for task in tasks where !seen.contains(task.lane.id) {
            lanes.append(task.lane)
            seen.insert(task.lane.id)
        }
        // An empty board has no column to drop a new task into, and no header
        // to hang the "new lane" button off.
        if lanes.isEmpty { lanes = Lane.starters }
        saveLanes()
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

    /// Reads the trashed notes. Anything under `trash/` without a `deleted:`
    /// stamp is treated as having been trashed just now rather than dropped —
    /// a file moved in by hand should still be recoverable, and giving it the
    /// full ten days is the forgiving reading.
    private func loadTrash() -> [Note] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" } ?? []

        var notes: [Note] = []
        var names: [UUID: String] = [:]

        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var note = NoteFile.decode(text)
            if note.deletedAt == nil { note.deletedAt = Clock.now() }
            notes.append(note)
            names[note.id] = url.lastPathComponent
        }

        trashFileNames = names
        return notes.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
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

    /// Removes a note outright — the file goes from disk with no way back.
    ///
    /// Private because nothing in the UI should reach it directly any more:
    /// deleting is `trashNote`, and the only routes to real destruction are
    /// emptying the trash, deleting from inside it, or the ten-day purge.
    private func destroyNote(id: UUID) {
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil

        if let i = notes.firstIndex(where: { $0.id == id }) {
            notes.remove(at: i)
            if let name = fileNames.removeValue(forKey: id) {
                try? FileManager.default.removeItem(at: notesDir.appendingPathComponent(name))
            }
        }
        if let i = trash.firstIndex(where: { $0.id == id }) {
            trash.remove(at: i)
            if let name = trashFileNames.removeValue(forKey: id) {
                try? FileManager.default.removeItem(at: trashDir.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Trash

    /// How long a trashed note is kept, in whole days.
    static let trashRetentionDays = 10

    /// Moves a note to the trash: out of `notes`, into `trash`, and its file
    /// from `notes/` to `trash/`.
    ///
    /// The file moves rather than being rewritten, so a note whose title has
    /// drifted from its filename keeps the name it already had — and the
    /// notes directory is left holding only notes.
    func trashNote(id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }

        // Anything still queued belongs to the version being trashed, and
        // would otherwise write the file back into `notes/` after the move.
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil

        var note = notes.remove(at: i)
        note.deletedAt = Clock.now()
        trash.insert(note, at: 0)

        let name = fileNames.removeValue(forKey: id) ?? NoteFile.filename(for: note)
        trashFileNames[id] = name
        move(note, named: name, from: notesDir, to: trashDir)
    }

    /// Trashes several notes as one action, so a bulk delete is one pass and
    /// one confirmation rather than a stutter of list updates.
    func trashNotes(ids: some Sequence<UUID>) {
        for id in ids { trashNote(id: id) }
    }

    /// Puts a note back where it came from, clearing its deletion stamp — and
    /// with it the countdown, which is only ever derived from that stamp.
    func restoreNote(id: UUID) {
        guard let i = trash.firstIndex(where: { $0.id == id }) else { return }

        var note = trash.remove(at: i)
        note.deletedAt = nil
        // Its folder may have been deleted while it sat in the trash, in which
        // case it comes back to Scratch rather than to a folder that is gone.
        if !folders.contains(note.folder) { note.folder = .scratch }
        notes.insert(note, at: 0)

        let name = trashFileNames.removeValue(forKey: id) ?? NoteFile.filename(for: note)
        fileNames[id] = name
        move(note, named: name, from: trashDir, to: notesDir)
    }

    /// Destroys one trashed note now, without waiting out its ten days.
    func deleteFromTrash(id: UUID) {
        guard trash.contains(where: { $0.id == id }) else { return }
        destroyNote(id: id)
    }

    func emptyTrash() {
        for note in trash { destroyNote(id: note.id) }
    }

    /// When a note trashed at `deletedAt` stops being recoverable: midnight at
    /// the end of its tenth full day, so a note trashed at 23:59 gets the same
    /// ten days as one trashed at 00:01.
    static func trashExpiry(deletedAt: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: deletedAt)
        return calendar.date(byAdding: .day, value: trashRetentionDays + 1, to: day) ?? day
    }

    /// Whole days left before `note` is purged, counting today. Zero means it
    /// goes at tonight's midnight.
    static func trashDaysRemaining(
        _ note: Note,
        asOf now: Date = Clock.now(),
        calendar: Calendar = .current
    ) -> Int {
        guard let deletedAt = note.deletedAt else { return trashRetentionDays }
        let lastDay = calendar.date(
            byAdding: .day, value: -1, to: trashExpiry(deletedAt: deletedAt, calendar: calendar)
        ) ?? now
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: lastDay)
        ).day ?? 0
        return max(0, days)
    }

    /// The trashed notes still within their ten days.
    ///
    /// Filtered here rather than trusting the purge to have run: expiry is a
    /// comparison against the clock, so an expired note is invisible whether
    /// or not the sweep that removes its file has happened yet. That makes the
    /// sweep a way of reclaiming disk, not the thing deciding what you see.
    func activeTrash(asOf now: Date = Clock.now()) -> [Note] {
        trash.filter { note in
            guard let deletedAt = note.deletedAt else { return true }
            return Store.trashExpiry(deletedAt: deletedAt) > now
        }
    }

    /// Destroys every trashed note past its ten days. Safe to call as often as
    /// you like — it touches the disk only when something has actually
    /// expired, and expiry lands on midnight, so running it hourly and running
    /// it daily delete the same files at the same observable moments.
    @discardableResult
    func purgeExpiredTrash(asOf now: Date = Clock.now()) -> Int {
        let expired = trash.filter { note in
            guard let deletedAt = note.deletedAt else { return false }
            return Store.trashExpiry(deletedAt: deletedAt) <= now
        }
        for note in expired { destroyNote(id: note.id) }
        return expired.count
    }

    /// Moves a note's file between the two directories, falling back to a
    /// rewrite if the move can't be done — the in-memory lists have already
    /// changed by this point, and a note that exists in one and not the other
    /// would come back from the dead on next launch.
    private func move(_ note: Note, named name: String, from source: URL, to destination: URL) {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let to = destination.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: to)

        // The stamp is part of the file, so the text is rewritten rather than
        // the bytes moved — `deleted:` has just been added or cleared.
        if (try? NoteFile.encode(note).write(to: to, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.removeItem(at: source.appendingPathComponent(name))
        }
    }

    // MARK: - Folders

    /// Creates a folder, or hands back the one that already has that name —
    /// typing a name that exists means "that folder", not a mistake.
    @discardableResult
    func addFolder(named name: String) -> Folder? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let folder = Folder(name)
        if let existing = folders.first(where: { $0 == folder }) { return existing }
        folders.append(folder)
        saveFolders()
        return folder
    }

    /// Renames in place, rewriting the notes inside it to match. Renaming onto
    /// a name that already exists merges the two — the alternative is two rows
    /// that mean the same folder, which nothing downstream could tell apart.
    func renameFolder(_ folder: Folder, to name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = folders.firstIndex(of: folder)
        else { return }

        let renamed = Folder(name)
        if renamed != folder, folders.contains(renamed) {
            folders.remove(at: index)
        } else {
            folders[index] = renamed
        }
        saveFolders()
        reassign(notesIn: folder, to: renamed)
    }

    /// Removing a folder keeps its notes — they fall back to Scratch, which is
    /// why Scratch itself can't be removed.
    func deleteFolder(_ folder: Folder) {
        guard folder != .scratch, let index = folders.firstIndex(of: folder) else { return }
        folders.remove(at: index)
        saveFolders()
        reassign(notesIn: folder, to: .scratch)
    }

    /// Moves notes between folders.
    ///
    /// Deliberately not `upsert`: that stamps `updatedAt`, and filing a note
    /// somewhere else isn't editing it — it would jump to the top of the list
    /// and claim it was edited just now.
    func move(noteIds: some Sequence<UUID>, to folder: Folder) {
        let ids = Set(noteIds)
        for i in notes.indices where ids.contains(notes[i].id) && notes[i].folder != folder {
            notes[i].folder = folder
            saveNote(notes[i])
        }
        if !folders.contains(folder) {
            folders.append(folder)
            saveFolders()
        }
    }

    /// Re-files every note in `folder`, including when only its capitalisation
    /// changed — the note's own copy of the name has to follow the rename.
    private func reassign(notesIn folder: Folder, to destination: Folder) {
        for i in notes.indices
        where notes[i].folder == folder && notes[i].folder.rawValue != destination.rawValue {
            notes[i].folder = destination
            saveNote(notes[i])
        }
    }

    private func saveFolders() { write(folders, to: foldersURL) }

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

    /// Writes the whole trash out, rebuilding the filename map — used after an
    /// import, where the notes arrived as values with no files behind them.
    private func saveTrash() {
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        trashFileNames = [:]
        for var note in trash {
            // An imported note that lost its stamp still gets a countdown,
            // rather than sitting in the trash forever.
            if note.deletedAt == nil { note.deletedAt = Clock.now() }
            let name = NoteFile.filename(for: note)
            trashFileNames[note.id] = name
            try? NoteFile.encode(note).write(
                to: trashDir.appendingPathComponent(name), atomically: true, encoding: .utf8
            )
        }
    }

    // MARK: - Lanes

    /// Where a task goes when the lane it named isn't on the board.
    ///
    /// The first column, because that is the one the board treats as the
    /// urgent end — a task with nowhere to go is better surfaced than buried.
    var defaultLane: Lane { lanes.first ?? .priority }

    /// Creates a lane, or hands back the one that already has that name —
    /// as with folders, typing an existing name means "that column".
    @discardableResult
    func addLane(named name: String) -> Lane? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lane = Lane(name)
        if let existing = lanes.first(where: { $0 == lane }) { return existing }
        lanes.append(lane)
        saveLanes()
        return lane
    }

    /// Renames in place, re-filing the tasks inside it. Renaming onto a name
    /// that already exists merges the two columns, for the same reason folders
    /// do: two rows meaning one lane is something nothing downstream — the
    /// board, the export, `tasks.json` — could tell apart.
    func renameLane(_ lane: Lane, to name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = lanes.firstIndex(of: lane)
        else { return }

        let renamed = Lane(name)
        if renamed != lane, lanes.contains(renamed) {
            lanes.remove(at: index)
        } else {
            lanes[index] = renamed
        }
        saveLanes()
        reassign(tasksIn: lane, to: renamed)
    }

    /// Removing a lane keeps its tasks — they fall back to the first column
    /// that's left, which is why the last remaining lane can't be removed.
    func deleteLane(_ lane: Lane) {
        guard lanes.count > 1, let index = lanes.firstIndex(of: lane) else { return }
        lanes.remove(at: index)
        saveLanes()
        reassign(tasksIn: lane, to: defaultLane)
    }

    /// Reorders the columns, moving `lane` so it sits at `index` in the list
    /// as it reads *after* the move.
    ///
    /// Taking a destination index rather than SwiftUI's `move(fromOffsets:
    /// toOffset:)` because the board is an `HStack` of columns, not a `List`:
    /// the drag hands over the lane it was dropped on, and "put it where that
    /// one is" is the whole gesture.
    func moveLane(_ lane: Lane, to index: Int) {
        guard let from = lanes.firstIndex(of: lane) else { return }
        let to = max(0, min(index, lanes.count - 1))
        guard from != to else { return }
        lanes.remove(at: from)
        lanes.insert(lane, at: to)
        saveLanes()
    }

    /// Re-files every task in `lane`, including when only its capitalisation
    /// changed — the task's own copy of the name has to follow the rename.
    private func reassign(tasksIn lane: Lane, to destination: Lane) {
        var touched = false
        for i in tasks.indices
        where tasks[i].lane == lane && tasks[i].lane.rawValue != destination.rawValue {
            tasks[i].lane = destination
            touched = true
        }
        if touched { saveTasks() }
    }

    private func saveLanes() { write(lanes, to: lanesURL) }

    // MARK: - Tasks

    /// Adds a task, snapping it to a column that exists.
    ///
    /// Callers name a lane by intent — the calendar's follow-up wants
    /// Delegate, a note's todo wants Priority — and that lane may since have
    /// been deleted. Landing in the default column is better than either
    /// resurrecting a lane the user removed or filing the task somewhere the
    /// board never draws.
    func addTask(_ task: TaskItem) {
        var task = task
        if !lanes.contains(task.lane) { task.lane = defaultLane }
        tasks.append(task)
        saveTasks()
    }

    func update(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i] = task
        saveTasks()
    }

    /// Edits a task's text in place.
    ///
    /// Separate from `update` so the row editor can hand over just the two
    /// fields it shows, without having to carry `done`, `completedAt` and
    /// `lane` through the edit and risk writing back a stale copy of them.
    /// A blank label is a cancelled edit, not a request for a nameless task.
    func edit(taskId: UUID, label: String, meta: String) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[i].label = label
        tasks[i].meta = meta.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if !lanes.contains(lane) {
            lanes.append(lane)
            saveLanes()
        }
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
        for directory in [notesDir, trashDir] {
            let existing = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in existing where url.pathExtension == "md" {
                try? FileManager.default.removeItem(at: url)
            }
        }

        notes = archive.notes
        trash = archive.trash ?? []
        tasks = archive.tasks
        log = archive.log
        milestones = archive.milestones

        // Older archives carry the folder on each note but no folder list, so
        // the sidebar is rebuilt from whatever arrived. Lanes are the same
        // story one step further on: an archive predating user-made lanes has
        // only the lane named on each task, and `reconcileLanes` rebuilds the
        // board from those.
        folders = archive.folders ?? Folder.starters
        lanes = archive.lanes ?? []
        reconcileFolders()
        reconcileLanes()

        saveNotes()
        saveTrash()
        saveTasks()
        saveLog()
        saveMilestones()

        // An archive can be old enough that notes in it are already past their
        // ten days, in which case importing shouldn't hand them back.
        purgeExpiredTrash()
    }
}
