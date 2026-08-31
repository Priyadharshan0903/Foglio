import Foundation

enum Clock {
    /// Every timestamp in the app is whole seconds.
    ///
    /// Both persisted formats — ISO8601 in the JSON files and in note
    /// frontmatter — are second-precision, so a raw `Date()` would silently lose
    /// its fraction the first time it was written and an export/import cycle
    /// would never be byte-identical. Truncating at the source keeps the
    /// in-memory value, the file on disk and a re-imported archive all equal,
    /// and nothing in a day log needs finer resolution than a second.
    static func now() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    static func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
