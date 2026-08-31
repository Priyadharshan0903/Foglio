import Foundation

enum NoteSpan: Equatable {
    case text(String)
    case link(String)
}

/// Port of `linkParts` (Day Log.dc.html:762): splits a paragraph into plain runs
/// and `[[wiki link]]` runs.
enum WikiLink {
    static func spans(in text: String) -> [NoteSpan] {
        var out: [NoteSpan] = []
        var rest = Substring(text)

        while let open = rest.range(of: "[[") {
            let before = rest[rest.startIndex..<open.lowerBound]
            guard let close = rest.range(of: "]]", range: open.upperBound..<rest.endIndex) else {
                break // unterminated — the remainder is plain text
            }
            if !before.isEmpty { out.append(.text(String(before))) }
            out.append(.link(String(rest[open.upperBound..<close.lowerBound])))
            rest = rest[close.upperBound...]
        }

        if !rest.isEmpty { out.append(.text(String(rest))) }
        return out
    }

    /// The design resolved a link by case-insensitive title *substring* (:768),
    /// so `[[Go worker pool]]` finds "Go worker pool" and `[[worker]]` would too.
    static func resolve(_ target: String, in titles: [String]) -> String? {
        let needle = target.lowercased()
        return titles.first { $0.lowercased().contains(needle) }
    }
}
