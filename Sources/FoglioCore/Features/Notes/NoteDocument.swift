import AppKit

/// Paragraph styles for the continuous editor. Markdown stays the disk format;
/// these attributes belong only to the text view, never to the saved file.
enum NoteStyle: String, CaseIterable {
    case body, title, heading, heading3, heading4, bullet, numbered, checklist, quote, divider, codeBlock, table, literal

    var label: String {
        switch self {
        case .body: "Body"
        case .title: "Title"
        case .heading: "Heading"
        case .heading3: "Heading 3"
        case .heading4: "Heading 4"
        case .bullet: "Bulleted list"
        case .numbered: "Numbered list"
        case .checklist: "Checklist"
        case .quote: "Quote"
        case .divider: "Divider"
        case .codeBlock: "Code block"
        case .table: "Table"
        case .literal: "Plain text"
        }
    }
}

extension NSAttributedString.Key {
    static let noteStyle = NSAttributedString.Key("FoglioNoteStyle")
    static let notePrefix = NSAttributedString.Key("FoglioNotePrefix")
}

enum NoteDocument {
    static func attributes(for style: NoteStyle, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let font: NSFont
        switch style {
        case .title: font = Typo.sansNSFont(23, .semibold)
        case .heading: font = Typo.sansNSFont(18, .semibold)
        case .heading3: font = Typo.sansNSFont(16, .semibold)
        case .heading4: font = Typo.sansNSFont(14, .semibold)
        case .literal, .codeBlock: font = Typo.monoNSFont(13)
        default: font = Typo.sansNSFont(14)
        }
        if [.bullet, .numbered].contains(style) { paragraph.headIndent = 22 }
        if style == .checklist {
            paragraph.headIndent = 26
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 26)]
            paragraph.paragraphSpacing = 3
        }
        if style == .quote { paragraph.firstLineHeadIndent = 14; paragraph.headIndent = 14 }
        if style == .codeBlock {
            paragraph.firstLineHeadIndent = 10
            paragraph.headIndent = 10
            paragraph.paragraphSpacing = 2
        }
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph,
                .noteStyle: style.rawValue]
    }

    /// Preserve original prefixes (including numbering and checkbox case) so
    /// opening a legacy note and editing prose doesn't rewrite other content.
    static func decode(_ markdown: String, color: NSColor, baseURL: URL? = nil) -> NSAttributedString {
        let lines = markdown.components(separatedBy: "\n")
        let result = NSMutableAttributedString(string: "")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let rich: NSAttributedString
            if line.hasPrefix("\u{0060}\u{0060}\u{0060}") || line.hasPrefix("~~~") {
                let fence = String(line.prefix(3))
                let end = ((index + 1)..<lines.count).first { lines[$0].hasPrefix(fence) } ?? lines.count
                let content = lines[(index + 1)..<end].joined(separator: "\n")
                var attrs = attributes(for: .codeBlock, color: color)
                attrs[.noteCodeID] = UUID().uuidString
                attrs[.noteCodeFence] = line
                attrs[.noteCodeBodyLines] = end - index - 1
                if end < lines.count { attrs[.noteCodeClose] = lines[end] }
                rich = NSAttributedString(string: content.isEmpty ? "\u{200B}" : content, attributes: attrs)
                index = end < lines.count ? end + 1 : end
            } else if line.contains("|"), index + 1 < lines.count, TableMarkdown.isSeparator(lines[index + 1]) {
                var end = index + 2
                while end < lines.count && lines[end].contains("|") && !lines[end].isEmpty { end += 1 }
                let tableLines = Array(lines[index..<end])
                let count = TableMarkdown.cells(line).count
                if tableLines.allSatisfy({ TableMarkdown.cells($0).count == count }) {
                    rich = TableMarkdown.decode(tableLines, color: color, baseURL: baseURL)
                } else {
                    rich = decodeLines(tableLines.joined(separator: "\n"), color: color, baseURL: baseURL)
                }
                index = end
            } else {
                rich = decodeLines(line, color: color, baseURL: baseURL)
                index += 1
            }
            result.append(rich)
            if index < lines.count {
                let attrs = rich.length > 0 ? rich.attributes(at: rich.length - 1, effectiveRange: nil) : attributes(for: .body, color: color)
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }
        return result
    }

    private static func decodeLines(_ markdown: String, color: NSColor, baseURL: URL?) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var fenced = false
        let lines = markdown.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            var style = NoteStyle.body
            var prefix = ""
            var display = line
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                fenced.toggle()
                style = .codeBlock
            } else if fenced {
                style = .codeBlock
            } else if line.hasPrefix("|") {
                style = .literal
            } else if let marker = prefixMatch("^#{1,6} ", in: line) {
                prefix = marker
                switch marker {
                case "# ": style = .title
                case "## ": style = .heading
                case "### ": style = .heading3
                case "#### ": style = .heading4
                default: style = .heading
                }
                display = String(line.dropFirst(marker.count))
            } else if let marker = prefixMatch("^[-*+] \\[([ xX])\\] ", in: line) {
                prefix = marker
                style = .checklist
                display = (marker.lowercased().contains("[x]") ? "☑\t" : "☐\t") + line.dropFirst(marker.count)
            } else if let marker = prefixMatch("^[-*+] ", in: line) {
                prefix = marker
                style = .bullet
                display = "• " + line.dropFirst(marker.count)
            } else if let marker = prefixMatch("^[0-9]{1,9}[.)] ", in: line) {
                prefix = marker
                style = .numbered
            } else if line.hasPrefix("> ") {
                prefix = "> "
                style = .quote
                display = String(line.dropFirst(2))
            } else if prefixMatch("^(-{3,}|_{3,}|\\*{3,})$", in: line) != nil {
                prefix = line
                style = .divider
                display = "―"
            }
            var attrs = attributes(for: style, color: color)
            // An empty attributed string cannot carry a paragraph attribute.
            // Keep a trailing empty heading verbatim until it has text.
            if display.isEmpty && !prefix.isEmpty && index == lines.count - 1 {
                display = line
                prefix = ""
                attrs = attributes(for: .literal, color: color)
            }
            if !prefix.isEmpty { attrs[.notePrefix] = prefix }
            if [.literal, .codeBlock, .divider].contains(style) {
                result.append(NSAttributedString(string: display, attributes: attrs))
            } else {
                let rich = NSMutableAttributedString(attributedString: InlineMarkdown.decode(display, attributes: attrs, baseURL: baseURL))
                rich.addAttributes([.noteInlineSource: display, .noteInlineCanonical: InlineMarkdown.encode(rich)],
                                   range: NSRange(location: 0, length: rich.length))
                result.append(rich)
            }
            if index < lines.count - 1 { result.append(NSAttributedString(string: "\n", attributes: attrs)) }
        }
        return result
    }

    static func encode(_ text: NSAttributedString) -> String {
        let ns = text.string as NSString
        var offset = 0
        return text.string.components(separatedBy: "\n").compactMap { display -> String? in
            defer { offset += (display as NSString).length + 1 }
            guard offset < ns.length else { return display }
            let attrs = text.attributes(at: offset, effectiveRange: nil)
            let style = NoteStyle(rawValue: attrs[.noteStyle] as? String ?? "") ?? .body
            let prefix = attrs[.notePrefix] as? String
            if let tableID = attrs[.noteTableID] as? String {
                if offset > 0, text.attribute(.noteTableID, at: offset - 1, effectiveRange: nil) as? String == tableID { return nil }
                var end = offset
                while end < text.length, text.attribute(.noteTableID, at: end, effectiveRange: nil) as? String == tableID {
                    end = ns.lineRange(for: NSRange(location: end, length: 0)).upperBound
                }
                if end > offset && ns.substring(with: NSRange(location: end - 1, length: 1)) == "\n" { end -= 1 }
                return TableMarkdown.encode(text.attributedSubstring(from: NSRange(location: offset, length: end - offset)))
            }
            let rich = text.attributedSubstring(from: NSRange(location: offset, length: display.utf16.count))
            let canonical = InlineMarkdown.encode(rich)
            let line = canonical == attrs[.noteInlineCanonical] as? String
                ? (attrs[.noteInlineSource] as? String ?? canonical) : canonical
            switch style {
            case .title: return (prefix ?? "# ") + line
            case .heading: return (prefix ?? "## ") + line
            case .heading3: return (prefix ?? "### ") + line
            case .heading4: return (prefix ?? "#### ") + line
            case .quote: return (prefix ?? "> ") + line
            case .divider: return prefix ?? "---"
            case .literal, .table: return display
            case .codeBlock:
                guard let codeID = attrs[.noteCodeID] as? String else { return display }
                var value = display.replacingOccurrences(of: "\u{200B}", with: "")
                let next = offset + display.utf16.count + 1
                let moreCode = next < text.length && text.attribute(.noteCodeID, at: next, effectiveRange: nil) as? String == codeID
                if offset == 0 || text.attribute(.noteCodeID, at: offset - 1, effectiveRange: nil) as? String != codeID {
                    let newline = !value.isEmpty || moreCode || (attrs[.noteCodeBodyLines] as? Int ?? 1) > 0 ? "\n" : ""
                    value = (attrs[.noteCodeFence] as? String ?? "\u{0060}\u{0060}\u{0060}") + newline + value
                }
                if !moreCode {
                    if let close = attrs[.noteCodeClose] as? String { value += "\n" + close }
                }
                return value
            case .bullet:
                return line.hasPrefix("• ") ? (prefix ?? "- ") + line.dropFirst(2) : line
            case .checklist:
                guard prefixMatch("^[☐☑][ \\t]", in: line) != nil else { return line }
                let checked = line.hasPrefix("☑")
                let marker: String
                if let prefix, prefix.lowercased().contains("[x]") == checked {
                    marker = prefix
                } else {
                    marker = String((prefix ?? "- ").prefix(2)) + (checked ? "[x] " : "[ ] ")
                }
                return marker + line.dropFirst(2)
            default: return line
            }
        }.joined(separator: "\n")
    }

    static func prefixMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
