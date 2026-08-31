import Foundation

enum TokenRole: Equatable {
    case comment, string, number, keyword, identifier, punctuation
}

struct Token: Equatable {
    let text: String
    let role: TokenRole
}

/// Port of `tokenize` (Day Log.dc.html:749) and `GO_KEYWORDS` (:639).
///
/// The design mapped tokens straight to CSS variables; here they map to roles
/// and the view picks the colour, so the tokenizer stays free of theme details.
enum GoSyntax {
    static let keywords: Set<String> = [
        "func", "for", "range", "if", "else", "return", "var", "const", "type",
        "struct", "go", "chan", "select", "case", "defer", "package", "import",
        "nil", "make", "new",
    ]

    /// One deliberate deviation from the design's regex: its final "everything
    /// else" group was `[^A-Za-z0-9_"]+`, which greedily eats `/` characters and
    /// so swallows any comment that doesn't start a line — `return nil // dropped`
    /// never highlighted as a comment upstream. The `(?!//)` guard stops that run
    /// at a comment opener so the comment branch gets its turn.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(//[^\n]*)|("(?:[^"\\]|\\.)*")|(\b\d+\b)|([A-Za-z_][A-Za-z0-9_]*)|((?:(?!//)[^A-Za-z0-9_"])+)"#
    )

    static func tokenize(_ line: String) -> [Token] {
        let ns = line as NSString
        var out: [Token] = []

        pattern.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            // Groups are ordered comment, string, number, identifier, other —
            // whichever matched decides the role.
            for group in 1...5 where match.range(at: group).location != NSNotFound {
                let text = ns.substring(with: match.range(at: group))
                let role: TokenRole
                switch group {
                case 1: role = .comment
                case 2: role = .string
                case 3: role = .number
                case 4: role = keywords.contains(text) ? .keyword : .identifier
                default: role = .punctuation
                }
                out.append(Token(text: text, role: role))
                break
            }
        }

        // The design emitted a single space for empty lines so the row keeps its
        // height (:760).
        return out.isEmpty ? [Token(text: " ", role: .identifier)] : out
    }
}
