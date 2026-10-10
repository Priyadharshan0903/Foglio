import AppKit

enum InlineFormat: String, CaseIterable {
    case bold, italic, underline, strike, code
    var label: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strike: "Strikethrough"
        case .code: "Inline code"
        }
    }
    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strike: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
    var key: NSAttributedString.Key { NSAttributedString.Key("FoglioInline-" + rawValue) }
}

extension NSAttributedString.Key {
    static let noteLink = NSAttributedString.Key("FoglioInlineLink")
    static let noteInlineSource = NSAttributedString.Key("FoglioInlineSource")
    static let noteInlineCanonical = NSAttributedString.Key("FoglioInlineCanonical")
    static let noteImageMarkdown = NSAttributedString.Key("FoglioImageMarkdown")
}

enum InlineMarkdown {
    private static let linkPattern = try! NSRegularExpression(pattern: #"^(!?)\[([^\]]*)\]\(([^\n)]+)\)"#)
    static func decode(_ text: String, attributes: [NSAttributedString.Key: Any], baseURL: URL? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var cursor = text.startIndex
        var plain = ""
        func append(_ value: String, _ attrs: [NSAttributedString.Key: Any]) {
            result.append(NSAttributedString(string: value, attributes: appearance(attrs)))
        }
        func flush() {
            if !plain.isEmpty { append(plain, attributes); plain = "" }
        }
        while cursor < text.endIndex {
            let rest = text[cursor...]
            if text[cursor] == "\\", text.index(after: cursor) < text.endIndex {
                let next = text.index(after: cursor)
                if #"!#$%&'()*+,-./:;<=>?@[\]^_{|}~"#.contains(text[next]) || text[next] == "\u{0060}" || text[next] == "\"" {
                    cursor = next
                    plain.append(text[cursor])
                    cursor = text.index(after: cursor)
                    continue
                }
            }
            if (rest.hasPrefix("[") || rest.hasPrefix("![")),
               let match = linkPattern.firstMatch(in: String(rest), range: NSRange(location: 0, length: rest.utf16.count)) {
                flush()
                let ns = String(rest) as NSString
                let label = ns.substring(with: match.range(at: 2))
                let target = ns.substring(with: match.range(at: 3))
                let source = ns.substring(with: match.range)
                if ns.substring(with: match.range(at: 1)) == "!" {
                    if let url = attachmentURL(target, baseURL: baseURL),
                       let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 20_000_000,
                       let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 {
                        let scale = min(1, min(460 / image.size.width, 260 / image.size.height))
                        let attachment = NSTextAttachment()
                        attachment.image = image
                        attachment.bounds = NSRect(x: 0, y: -4, width: image.size.width * scale, height: image.size.height * scale)
                        let rich = NSMutableAttributedString(attachment: attachment)
                        var attrs = attributes
                        attrs[.noteImageMarkdown] = source
                        rich.addAttributes(attrs, range: NSRange(location: 0, length: rich.length))
                        result.append(rich)
                    } else { append(source, attributes) }
                } else {
                    var attrs = attributes
                    attrs[.noteLink] = target
                    if let url = attachmentURL(target, baseURL: baseURL) ?? safeURL(target) { attrs[.link] = url }
                    result.append(decode(label, attributes: attrs, baseURL: baseURL))
                }
                cursor = text.index(cursor, offsetBy: source.count)
                continue
            }
            let tokens: [(String, String, InlineFormat)] = [
                ("**", "**", .bold), ("__", "__", .bold), ("~~", "~~", .strike),
                ("<u>", "</u>", .underline), ("\u{0060}", "\u{0060}", .code), ("*", "*", .italic), ("_", "_", .italic),
            ]
            var consumed = false
            for (open, close, format) in tokens where rest.hasPrefix(open) {
                let beginning = text.index(cursor, offsetBy: open.count)
                guard let end = text.range(of: close, range: beginning..<text.endIndex), end.lowerBound > beginning else { continue }
                var attrs = attributes
                attrs[format.key] = open
                flush()
                let content = String(text[beginning..<end.lowerBound])
                if format == .code { append(content, attrs) }
                else { result.append(decode(content, attributes: attrs, baseURL: baseURL)) }
                cursor = end.upperBound
                consumed = true
                break
            }
            if consumed { continue }
            plain.append(text[cursor])
            cursor = text.index(after: cursor)
        }
        flush()
        return result
    }

    /// A common-prefix stack keeps overlapping selections well formed.
    static func encode(_ text: NSAttributedString) -> String {
        struct Token: Equatable { let open: String; let close: String }
        var stack: [Token] = []
        var output = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            var next: [Token] = []
            if let url = attrs[.noteLink] as? String { next.append(Token(open: "[", close: "](" + url + ")")) }
            for format in InlineFormat.allCases {
                if let delimiter = attrs[format.key] as? String {
                    next.append(Token(open: delimiter, close: format == .underline ? "</u>" : delimiter))
                }
            }
            let common = zip(stack, next).prefix { $0 == $1 }.count
            for token in stack.dropFirst(common).reversed() { output += token.close }
            for token in next.dropFirst(common) { output += token.open }
            stack = next
            if let source = attrs[.noteImageMarkdown] as? String, attrs[.attachment] != nil {
                output += source
            } else {
                let value = (text.string as NSString).substring(with: range)
                output += attrs[InlineFormat.code.key] != nil ? value : escape(value)
            }
        }
        for token in stack.reversed() { output += token.close }
        return output
    }

    static func appearance(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attrs = attributes
        let style = NoteStyle(rawValue: attrs[.noteStyle] as? String ?? "") ?? .body
        let color = attrs[.foregroundColor] as? NSColor ?? .labelColor
        var font = NoteDocument.attributes(for: style, color: color)[.font] as! NSFont
        if attrs[InlineFormat.code.key] != nil {
            font = Typo.monoNSFont(13)
            attrs[.backgroundColor] = color.withAlphaComponent(0.09)
        } else { attrs.removeValue(forKey: .backgroundColor) }
        let bold = attrs[InlineFormat.bold.key] != nil || attrs[.noteTableHeader] as? Bool == true
        if bold {
            font = attrs[InlineFormat.code.key] != nil ? Typo.monoNSFont(font.pointSize, .semibold) : Typo.sansNSFont(font.pointSize, .semibold)
        }
        if attrs[InlineFormat.italic.key] != nil {
            let converted = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            font = NSFontManager.shared.traits(of: converted).contains(.italicFontMask)
                ? converted : NSFontManager.shared.convert(.systemFont(ofSize: font.pointSize, weight: bold ? .semibold : .regular), toHaveTrait: .italicFontMask)
        }
        if let paragraph = attrs[.paragraphStyle] as? NSParagraphStyle {
            for block in paragraph.textBlocks {
                block.setBorderColor(color.withAlphaComponent(0.18))
                block.backgroundColor = attrs[.noteTableHeader] as? Bool == true ? color.withAlphaComponent(0.04) : nil
            }
        }
        attrs[.font] = font
        if attrs[InlineFormat.underline.key] != nil || attrs[.noteLink] != nil { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        else { attrs.removeValue(forKey: .underlineStyle) }
        if attrs[InlineFormat.strike.key] != nil { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        else { attrs.removeValue(forKey: .strikethroughStyle) }
        return attrs
    }

    static func safeURL(_ text: String) -> URL? {
        guard let url = URL(string: text), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    static func attachmentURL(_ target: String, baseURL: URL?) -> URL? {
        guard target.hasPrefix("attachments/"), let baseURL else { return nil }
        let root = baseURL.appendingPathComponent("attachments").standardizedFileURL
        let url = baseURL.appendingPathComponent(target).standardizedFileURL
        return url.path.hasPrefix(root.path + "/") ? url : nil
    }
    private static func escape(_ text: String) -> String {
        var output = ""
        for character in text {
            if "\\*_\u{0060}~[]".contains(character) { output += "\\" }
            output.append(character)
        }
        return output
    }
}
