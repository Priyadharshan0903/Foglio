import Foundation

/// A note on disk: YAML-ish frontmatter followed by the markdown body.
///
///     ---
///     title: Operator — reconcile loop notes
///     folder: platform
///     pin: Kubernetes, to CKA
///     updated: 2026-08-31T14:20:00Z
///     ---
///     # Reconcile, don't RPC
///
/// Values run to end-of-line and are never quoted, so a title containing a colon
/// round-trips fine. Anything the parser doesn't recognise is ignored rather
/// than treated as an error — these files are meant to be hand-editable.
enum NoteFile {
    private static let fence = "---"

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func encode(_ note: Note) -> String {
        var head = [
            "\(fence)",
            "id: \(note.id.uuidString)",
            "title: \(note.title)",
            "folder: \(note.folder.rawValue)",
        ]
        if let pin = note.pin, !pin.isEmpty {
            head.append("pin: \(pin)")
        }
        head.append("updated: \(formatter.string(from: note.updatedAt))")
        head.append(fence)
        return head.joined(separator: "\n") + "\n" + note.body
    }

    static func decode(_ text: String) -> Note {
        var note = Note()
        let lines = text.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == fence,
              let closing = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == fence
              })
        else {
            // No frontmatter — treat the whole file as the body.
            note.body = text
            return note
        }

        for line in lines[1..<closing] {
            guard let split = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<split]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: split)...])
                .trimmingCharacters(in: .whitespaces)

            switch key {
            case "id": note.id = UUID(uuidString: value) ?? note.id
            case "title": note.title = value
            case "folder": note.folder = Folder(rawValue: value) ?? .scratch
            case "pin": note.pin = value.isEmpty ? nil : value
            case "updated": note.updatedAt = formatter.date(from: value) ?? note.updatedAt
            default: break
            }
        }

        note.body = lines[(closing + 1)...].joined(separator: "\n")
        return note
    }

    /// A stable, human-meaningful filename. Collisions are broken by the id so
    /// two notes titled the same don't overwrite each other.
    static func filename(for note: Note) -> String {
        let slug = note.title
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { acc, ch in
                if ch == "-" && acc.hasSuffix("-") { return }
                acc.append(ch)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let stem = slug.isEmpty ? "untitled" : String(slug.prefix(60))
        return "\(stem)-\(note.id.uuidString.prefix(8)).md"
    }
}
