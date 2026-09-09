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
    /// One item of a numbered list. The number is *not* stored: it comes from
    /// how many ordered items precede it in an unbroken run, so inserting,
    /// deleting or reordering items renumbers the list for free — and a file
    /// hand-edited into `1. 1. 1.` still reads back as 1, 2, 3.
    case orderedItem(String)
    case todo(text: String, checked: Bool)
    case code(language: String, text: String)
    case table(rows: [[String]])
    case image(alt: String, path: String)
    case divider

    /// The plain text of the block, for snippets and search.
    var plainText: String {
        switch self {
        case .h1(let t), .h2(let t), .paragraph(let t), .listItem(let t), .orderedItem(let t):
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

    /// Blocks that come in runs, where Return should give you another one.
    /// A checklist counts: it's a list whose marker happens to be a box.
    var isListItem: Bool {
        switch self {
        case .listItem, .orderedItem, .todo: return true
        default: return false
        }
    }

    /// What pressing Return at the end of this block should create.
    ///
    /// Lists continue themselves — typing five bullets shouldn't mean clicking
    /// "Bullets" five times — and everything else starts a plain paragraph.
    var continuation: Block {
        switch self {
        case .listItem: return .listItem("")
        case .orderedItem: return .orderedItem("")
        case .todo: return .todo(text: "", checked: false)
        default: return .paragraph("")
        }
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
