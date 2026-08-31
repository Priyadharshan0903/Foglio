import Foundation

/// One editor block. Mirrors the design's block union (Day Log.dc.html:647-661).
///
/// Deliberately missing: the design's `sent` flag on todos, which records that a
/// todo was pushed to the task lanes. That isn't a markdown concept, and storing
/// it would pollute the file format. It's derived instead — a todo reads as
/// "in tasks" when a `TaskItem` with the same label exists. That also behaves
/// better than the original: deleting the task makes the todo sendable again,
/// where the design latched `sent` permanently.
enum Block: Equatable {
    case h1(String)
    case h2(String)
    case paragraph(String)
    case listItem(String)
    case todo(text: String, checked: Bool)
    case code(language: String, text: String)
    case table(rows: [[String]])
    case image(alt: String, path: String)
    case divider

    /// The plain text of the block, for snippets and search.
    var plainText: String {
        switch self {
        case .h1(let t), .h2(let t), .paragraph(let t), .listItem(let t):
            return t
        case .todo(let t, _):
            return t
        case .code(_, let t):
            return t
        case .table(let rows):
            return rows.flatMap { $0 }.joined(separator: " ")
        case .image(let alt, _):
            return alt
        case .divider:
            return ""
        }
    }

    var isTodo: Bool {
        if case .todo = self { return true }
        return false
    }

    /// Code and tables are edited as multi-line raw text and don't re-parse
    /// their type on every keystroke (matches `parseRaw`'s `prev` guard, :740).
    var isMultiline: Bool {
        switch self {
        case .code, .table: return true
        default: return false
        }
    }
}
