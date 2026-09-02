import Foundation

/// Turns whatever the user points at into iCalendar text.
///
/// Needed because Google's "Import & export ▸ Export" hands you a **zip**
/// (`<address>.ical.zip`) containing one `.ics` per calendar — pointing the app
/// at that file directly would simply fail. And because re-exporting doesn't
/// overwrite, it lands as `… (1).zip`, `… (2).zip`, so remembering one exact
/// filename goes stale on the second export.
///
/// So a *folder* is also a valid target: point Foglio at Downloads, export
/// whenever you like, and the newest export is picked up on the next refresh.
enum ICSImporter {
    enum Failure: LocalizedError {
        case unreadable
        case noCalendarFound(in: String)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "Couldn't read that file."
            case .noCalendarFound(let where_):
                "No .ics or .zip export found in \(where_)."
            }
        }
    }

    /// Resolves a file or folder to calendar text.
    static func read(_ url: URL) throws -> String {
        if isDirectory(url) {
            guard let newest = newestExport(in: url) else {
                throw Failure.noCalendarFound(in: url.lastPathComponent)
            }
            return try readFile(newest)
        }
        return try readFile(url)
    }

    /// A short description of what will actually be read, for the UI.
    static func describe(_ url: URL) -> String {
        if isDirectory(url) {
            guard let newest = newestExport(in: url) else {
                return "\(url.lastPathComponent) — no export found yet"
            }
            return "\(url.lastPathComponent)/\(newest.lastPathComponent)"
        }
        return url.lastPathComponent
    }

    /// When the export we'd actually read was written — i.e. how current the
    /// snapshot is. There is no live sync available, so surfacing this honestly
    /// is the difference between a useful view and a quietly wrong one.
    static func exportedAt(_ url: URL) -> Date? {
        let target = isDirectory(url) ? newestExport(in: url) : url
        guard let target else { return nil }
        return try? target.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// The most recently modified calendar export in a folder.
    static func newestExport(in directory: URL) -> URL? {
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidates
            // Google names its export `<address>.ical.zip`; a plain .ics file is
            // equally welcome. Other zips in Downloads are ignored.
            .filter { url in
                let ext = url.pathExtension.lowercased()
                return ext == "ics"
                    || (ext == "zip" && url.lastPathComponent.lowercased().contains("ical"))
            }
            .max { a, b in modified(a) < modified(b) }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private static func readFile(_ url: URL) throws -> String {
        if url.pathExtension.lowercased() == "zip" {
            return try unzipCalendars(url)
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw Failure.unreadable
        }
        return text
    }

    /// Streams every `.ics` inside the archive to stdout and concatenates them.
    ///
    /// A Google export holds one entry per calendar; the parser only looks for
    /// VEVENT blocks, so concatenating them is exactly right.
    private static func unzipCalendars(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "*.ics"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw Failure.unreadable
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else {
            throw Failure.noCalendarFound(in: url.lastPathComponent)
        }
        return text
    }
}
