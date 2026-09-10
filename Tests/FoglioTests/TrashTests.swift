import Foundation
@testable import FoglioCore

@MainActor
func trashTests() {
    func freshStore() -> (Store, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        let store = Store(root: root)
        store.load()
        return (store, root)
    }

    func fileCount(_ root: URL, _ dir: String) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(dir).path)) ?? [])
            .filter { $0.hasSuffix(".md") }.count
    }

    /// A date at a given hour on a day `daysAgo` before now, so a test can put
    /// a note in the trash at a precise point in its ten days.
    func day(_ daysAgo: Int, hour: Int = 12) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Clock.now())
        let shifted = cal.date(byAdding: .day, value: -daysAgo, to: start)!
        return cal.date(byAdding: .hour, value: hour, to: shifted)!
    }

    Check.suite("Trash — the ten days are whole days") {
        let cal = Calendar.current

        // Deleted at one minute past midnight and at one minute to it are the
        // same day, so they have to expire together — otherwise the countdown
        // would say "10 days left" to two notes that die 24 hours apart.
        let early = Store.trashExpiry(deletedAt: day(0, hour: 0))
        let late = Store.trashExpiry(deletedAt: day(0, hour: 23))
        Check.equal(early, late, "time of day doesn't change when a note expires")
        Check.equal(
            cal.dateComponents([.hour, .minute], from: early).hour, 0,
            "and expiry lands on midnight"
        )

        // Trashed today, so today plus ten more whole days.
        let expiry = Store.trashExpiry(deletedAt: day(0))
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Clock.now()), to: expiry).day
        Check.equal(days, Store.trashRetentionDays + 1, "a note trashed today survives all ten days")

        // The guarantee that motivates the rule: nothing gets less than ten
        // full days, whatever time of day it was trashed.
        let latest = day(0, hour: 23)
        Check.expect(
            Store.trashExpiry(deletedAt: latest).timeIntervalSince(latest)
                >= Double(Store.trashRetentionDays) * 86_400,
            "even a note trashed just before midnight gets its full ten days"
        )
    }

    Check.suite("Trash — the countdown") {
        var fresh = Note(title: "Just gone")
        fresh.deletedAt = day(0)
        Check.equal(Store.trashDaysRemaining(fresh), 10, "trashed today reads as ten days left")

        var midway = Note(title: "Halfway")
        midway.deletedAt = day(5)
        Check.equal(Store.trashDaysRemaining(midway), 5, "five days in, five days left")

        var lastDay = Note(title: "Tonight")
        lastDay.deletedAt = day(10)
        Check.equal(Store.trashDaysRemaining(lastDay), 0, "on its last day it goes tonight")

        // Past expiry the count can't go negative — the row is gone by then,
        // but a stale render must not say "-3 days left".
        var over = Note(title: "Overdue")
        over.deletedAt = day(30)
        Check.equal(Store.trashDaysRemaining(over), 0, "an expired note never counts below zero")
    }

    Check.suite("Trash — moving a note in") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var note = store.newNote(in: .platform)
        note.title = "Second thoughts"
        note.body = "Maybe not."
        store.upsert(note)

        let notesBefore = fileCount(root, "notes")
        store.trashNote(id: note.id)

        Check.expect(store.note(id: note.id) == nil, "it leaves the note list")
        Check.equal(fileCount(root, "notes"), notesBefore - 1, "and the notes directory")
        Check.equal(fileCount(root, "trash"), 1, "the file is in trash/, not deleted")
        Check.expect(store.trash.first?.deletedAt != nil, "and it is stamped with when it went")

        // The stamp lives in the file, so the trash and its countdowns survive
        // a relaunch — this is what makes the ten days mean anything.
        let reopened = Store(root: root)
        reopened.load()
        Check.equal(reopened.trash.count, 1, "the trash survives a relaunch")
        Check.equal(reopened.trash.first?.title, "Second thoughts", "with the note intact")
        Check.equal(reopened.trash.first?.body, "Maybe not.", "body and all")
        Check.expect(reopened.trash.first?.deletedAt != nil, "and its deletion stamp")
        Check.expect(
            !reopened.notes.contains { $0.id == note.id },
            "a trashed note does not come back as a live note"
        )
    }

    Check.suite("Trash — a trashed note is invisible to everything else") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var note = store.newNote(in: .platform)
        note.title = "Findable"
        note.body = "unique-token-xyz"
        store.upsert(note)
        Check.expect(store.notes.contains { $0.matches("unique-token-xyz") }, "found while it lives")
        let inFolder = store.notes.filter { $0.folder == .platform }.count

        store.trashNote(id: note.id)
        // The whole reason the trash is a separate list: search, folder counts,
        // pin targets and the export all read `notes`, and none of them had to
        // learn the trash exists.
        Check.expect(
            !store.notes.contains { $0.matches("unique-token-xyz") },
            "and not found once trashed"
        )
        Check.equal(
            store.notes.filter { $0.folder == .platform }.count,
            inFolder - 1,
            "it stops counting towards its folder"
        )
    }

    Check.suite("Trash — putting a note back") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var note = store.newNote(in: .career)
        note.title = "Wanted after all"
        store.upsert(note)
        let notesOnDisk = fileCount(root, "notes")
        store.trashNote(id: note.id)
        store.restoreNote(id: note.id)

        let back = store.note(id: note.id)
        Check.expect(back != nil, "it is a live note again")
        Check.equal(back?.title, "Wanted after all", "with its title")
        Check.equal(back?.folder, .career, "back in the folder it came from")
        // The countdown is derived from the stamp and nothing else, so
        // clearing the stamp is what removes the hard-delete time.
        Check.expect(back?.deletedAt == nil, "and no deletion stamp, so no countdown")
        Check.equal(store.trash.count, 0, "the trash is empty again")
        Check.equal(fileCount(root, "trash"), 0, "and the file left trash/")
        Check.equal(fileCount(root, "notes"), notesOnDisk, "for notes/")

        let reopened = Store(root: root)
        reopened.load()
        Check.expect(reopened.notes.contains { $0.id == note.id }, "the restore survives a relaunch")
        Check.equal(reopened.trash.count, 0, "with nothing left in the trash")
    }

    Check.suite("Trash — restoring into a folder that has since gone") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        store.addFolder(named: "Temporary")
        var note = store.newNote(in: Folder("Temporary"))
        note.title = "Orphan"
        store.upsert(note)
        store.trashNote(id: note.id)
        store.deleteFolder(Folder("Temporary"))

        store.restoreNote(id: note.id)
        Check.equal(
            store.note(id: note.id)?.folder,
            .scratch,
            "a note whose folder went while it sat in the trash comes back to Scratch"
        )
    }

    Check.suite("Trash — the ten-day purge") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        @MainActor func trash(_ title: String) -> UUID {
            var note = store.newNote(in: .scratch)
            note.title = title
            store.upsert(note)
            store.trashNote(id: note.id)
            return note.id
        }

        let a = trash("First")
        let b = trash("Second")
        Check.equal(store.trash.count, 2, "two notes in the trash")

        // Everything trashed today shares one expiry, so the boundary can be
        // walked directly rather than by faking stamps into the past.
        let expiry = Store.trashExpiry(deletedAt: store.trash[0].deletedAt!)

        let justBefore = expiry.addingTimeInterval(-1)
        Check.equal(store.activeTrash(asOf: justBefore).count, 2, "a second before expiry both are live")
        Check.equal(store.purgeExpiredTrash(asOf: justBefore), 0, "and the sweep takes neither")

        Check.equal(store.activeTrash(asOf: expiry).count, 0, "at expiry they stop being visible")
        Check.expect(store.trash.count == 2, "even though the sweep hasn't run — that is read-time filtering")

        Check.equal(store.purgeExpiredTrash(asOf: expiry), 2, "then the sweep takes both")
        Check.expect(!store.trash.contains { $0.id == a || $0.id == b }, "they leave the list")
        Check.equal(fileCount(root, "trash"), 0, "and their files leave disk")
        Check.equal(store.purgeExpiredTrash(asOf: expiry), 0, "sweeping again finds nothing — it is idempotent")
    }

    Check.suite("Trash — an expired note is purged at launch") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        // Written straight to disk, dated well past its ten days: this is what
        // the store finds after the app has been closed for a fortnight.
        let trashDir = root.appendingPathComponent("trash")
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        var stale = Note(title: "Closed for a fortnight", folder: .scratch)
        stale.deletedAt = day(30)
        try? NoteFile.encode(stale).write(
            to: trashDir.appendingPathComponent(NoteFile.filename(for: stale)),
            atomically: true, encoding: .utf8
        )

        var fresh = Note(title: "Trashed yesterday", folder: .scratch)
        fresh.deletedAt = day(1)
        try? NoteFile.encode(fresh).write(
            to: trashDir.appendingPathComponent(NoteFile.filename(for: fresh)),
            atomically: true, encoding: .utf8
        )

        let store = Store(root: root)
        store.load()

        Check.equal(store.trash.count, 1, "the expired note is purged before anything can render")
        Check.equal(store.trash.first?.title, "Trashed yesterday", "and the one still in date is kept")
        Check.equal(
            fileCount(root, "trash"), 1,
            "the purge reached disk, so it stays purged next launch"
        )
    }

    Check.suite("Trash — a hand-dropped file is recoverable") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foglio-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        // These are plain markdown files in a plain directory, so someone can
        // move one in by hand. With no stamp to date it, the forgiving reading
        // is that its ten days start now rather than that it expired long ago.
        let trashDir = root.appendingPathComponent("trash")
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        try? "---\ntitle: Dropped in by hand\n---\nbody".write(
            to: trashDir.appendingPathComponent("hand-written.md"), atomically: true, encoding: .utf8
        )

        let store = Store(root: root)
        store.load()
        Check.equal(store.trash.count, 1, "it is picked up rather than ignored")
        Check.expect(store.trash.first?.deletedAt != nil, "and given a stamp")
        Check.equal(store.activeTrash().count, 1, "so it is recoverable rather than instantly expired")
    }

    Check.suite("Trash — deleting for good") {
        let (store, root) = freshStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var keep = store.newNote(in: .scratch)
        keep.title = "Keep"
        store.upsert(keep)
        var burn = store.newNote(in: .scratch)
        burn.title = "Burn"
        store.upsert(burn)

        store.trashNote(id: keep.id)
        store.trashNote(id: burn.id)
        store.deleteFromTrash(id: burn.id)

        Check.equal(store.trash.count, 1, "only the chosen note is destroyed")
        Check.equal(store.trash.first?.id, keep.id, "and it is the right one that survives")
        Check.equal(fileCount(root, "trash"), 1, "its file goes with it")

        // A live note must not be destroyable through the trash's door.
        var live = store.newNote(in: .scratch)
        live.title = "Still mine"
        store.upsert(live)
        store.deleteFromTrash(id: live.id)
        Check.expect(store.note(id: live.id) != nil, "deleteFromTrash ignores a note that isn't in the trash")

        store.emptyTrash()
        Check.equal(store.trash.count, 0, "emptying clears the list")
        Check.equal(fileCount(root, "trash"), 0, "and the directory")
        Check.expect(store.note(id: live.id) != nil, "without touching live notes")
    }

    Check.suite("Trash — surviving export and import") {
        let (source, sourceRoot) = freshStore()
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        var note = source.newNote(in: .platform)
        note.title = "In the bin"
        source.upsert(note)
        source.trashNote(id: note.id)

        let archive = Exporter.archive(from: source)
        Check.equal(archive.trash?.count, 1, "the archive carries the trash")
        Check.expect(archive.trash?.first?.deletedAt != nil, "with the deletion stamp that dates it")

        let (destination, destinationRoot) = freshStore()
        defer { try? FileManager.default.removeItem(at: destinationRoot) }
        destination.replaceAll(with: archive)

        Check.equal(destination.trash.count, 1, "importing restores it as still-trashed")
        Check.expect(
            !destination.notes.contains { $0.id == note.id },
            "rather than handing it back as a live note"
        )
        Check.equal(fileCount(destinationRoot, "trash"), 1, "with a file behind it")

        // An archive old enough that its trash has expired shouldn't resurrect
        // notes that were already past saving when it was written.
        var stale = Note(title: "Expired before import")
        stale.deletedAt = day(30)
        destination.replaceAll(with: Archive(notes: [], trash: [stale], folders: nil, lanes: nil))
        Check.equal(destination.trash.count, 0, "an expired note is purged on import")

        // An archive from before there was a trash has no key at all.
        destination.replaceAll(with: Archive(notes: [], folders: nil, lanes: nil))
        Check.equal(destination.trash.count, 0, "an archive without the key imports an empty trash")
    }
}
