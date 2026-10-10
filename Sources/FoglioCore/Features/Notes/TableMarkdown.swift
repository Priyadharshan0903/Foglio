import AppKit

enum TableEditAction { case addRow, addColumn, deleteRow, deleteColumn, remove }

extension NSAttributedString.Key {
    static let noteTableID = NSAttributedString.Key("FoglioTableID")
    static let noteTableRow = NSAttributedString.Key("FoglioTableRow")
    static let noteTableColumn = NSAttributedString.Key("FoglioTableColumn")
    static let noteTableHeader = NSAttributedString.Key("FoglioTableHeader")
    static let noteTableSource = NSAttributedString.Key("FoglioTableSource")
    static let noteTableCanonical = NSAttributedString.Key("FoglioTableCanonical")
    static let noteTableSeparator = NSAttributedString.Key("FoglioTableSeparator")
    static let noteCodeID = NSAttributedString.Key("FoglioCodeID")
    static let noteCodeFence = NSAttributedString.Key("FoglioCodeFence")
    static let noteCodeClose = NSAttributedString.Key("FoglioCodeClose")
    static let noteCodeBodyLines = NSAttributedString.Key("FoglioCodeBodyLines")
}

extension NoteTextView {
    func editTable(_ action: TableEditAction) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let index = min(selectedRange().location, storage.length - 1)
        guard let id = storage.attribute(.noteTableID, at: index, effectiveRange: nil) as? String else { return }
        let attrs = storage.attributes(at: index, effectiveRange: nil)
        let ns = storage.string as NSString
        var start = index
        while start > 0, storage.attribute(.noteTableID, at: start - 1, effectiveRange: nil) as? String == id { start -= 1 }
        var end = index
        while end < storage.length, storage.attribute(.noteTableID, at: end, effectiveRange: nil) as? String == id { end += 1 }
        let trailingNewline = end > start && ns.substring(with: NSRange(location: end - 1, length: 1)) == "\n"
        let range = NSRange(location: start, length: end - start)
        let existing = storage.attributedSubstring(from: range)
        var rows = TableMarkdown.encode(existing).components(separatedBy: "\n").map(TableMarkdown.cells)
        guard rows.count >= 2, let columns = rows.first?.count, columns > 0 else { return }
        switch action {
        case .addRow: rows.append(Array(repeating: "", count: columns))
        case .addColumn:
            for row in rows.indices { rows[row].append(row == 0 ? "Column \(columns + 1)" : row == 1 ? "---" : "") }
        case .deleteRow:
            guard let row = attrs[.noteTableRow] as? Int, row > 0, row + 1 < rows.count else { return }
            rows.remove(at: row + 1)
        case .deleteColumn:
            guard columns > 1, let column = attrs[.noteTableColumn] as? Int, column < columns else { return }
            for row in rows.indices where rows[row].count > column { rows[row].remove(at: column) }
        case .remove:
            let plain = rows.enumerated().filter { $0.offset != 1 }.map { $0.element.joined(separator: " · ") }.joined(separator: "\n")
            replace(range, with: NSAttributedString(string: plain + (trailingNewline ? "\n" : ""), attributes: NoteDocument.attributes(for: .body, color: ink)))
            setSelectedRange(NSRange(location: start, length: 0))
            return
        }
        let markdown = rows.map { "| " + $0.joined(separator: " | ") + " |" }.joined(separator: "\n")
        let replacement = NSMutableAttributedString(attributedString: NoteDocument.decode(markdown, color: ink, baseURL: attachmentBaseURL))
        if trailingNewline {
            replacement.append(NSAttributedString(string: "\n", attributes: replacement.attributes(at: replacement.length - 1, effectiveRange: nil)))
        }
        replace(range, with: replacement)
        setSelectedRange(NSRange(location: start, length: 0))
        window?.makeFirstResponder(self)
    }
}

enum TableMarkdown {
    static func cells(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        var cells = [String]()
        var cell = ""
        var escaped = false
        for character in content {
            if character == "|" && !escaped { cells.append(cell.trimmingCharacters(in: .whitespaces)); cell = "" }
            else { cell.append(character) }
            escaped = character == "\\" && !escaped
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }
    static func isSeparator(_ line: String) -> Bool {
        let values = cells(line)
        return !values.isEmpty && values.allSatisfy { $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }
    }
    static func decode(_ lines: [String], color: NSColor, baseURL: URL?) -> NSAttributedString {
        let rows = ([lines[0]] + lines.dropFirst(2)).map(cells)
        let columns = cells(lines[0]).count
        let alignment = cells(lines[1])
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.setContentWidth(100, type: .percentageValueType)
        table.setWidth(2, type: .absoluteValueType, for: .margin)
        let result = NSMutableAttributedString(string: "")
        let id = UUID().uuidString
        for (rowIndex, row) in rows.enumerated() {
            for column in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(color.withAlphaComponent(0.18))
                if rowIndex == 0 { block.backgroundColor = color.withAlphaComponent(0.04) }
                var attrs = NoteDocument.attributes(for: .table, color: color)
                let paragraph = (attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
                paragraph.textBlocks = [block]
                paragraph.lineSpacing = 2
                let align = column < alignment.count ? alignment[column] : "---"
                if align.hasPrefix(":") && align.hasSuffix(":") { paragraph.alignment = .center }
                else if align.hasSuffix(":") { paragraph.alignment = .right }
                attrs[.paragraphStyle] = paragraph
                attrs[.noteTableID] = id
                attrs[.noteTableRow] = rowIndex
                attrs[.noteTableColumn] = column
                attrs[.noteTableHeader] = rowIndex == 0
                attrs[.noteTableSeparator] = lines[1]
                let value = column < row.count ? row[column].replacingOccurrences(of: "<br>", with: "\u{2028}") : ""
                result.append(InlineMarkdown.decode(value.isEmpty ? "\u{200B}" : value, attributes: attrs, baseURL: baseURL))
                if rowIndex < rows.count - 1 || column < columns - 1 { result.append(NSAttributedString(string: "\n", attributes: attrs)) }
            }
        }
        let canonical = encode(result, preserveSource: false)
        result.addAttributes([.noteTableSource: lines.joined(separator: "\n"), .noteTableCanonical: canonical],
                             range: NSRange(location: 0, length: result.length))
        return result
    }
    static func encode(_ text: NSAttributedString, preserveSource: Bool = true) -> String {
        var rows: [Int: [Int: String]] = [:]
        var offset = 0
        for value in text.string.components(separatedBy: "\n") {
            defer { offset += value.utf16.count + 1 }
            guard offset < text.length else { continue }
            let attrs = text.attributes(at: offset, effectiveRange: nil)
            guard let row = attrs[.noteTableRow] as? Int, let column = attrs[.noteTableColumn] as? Int else { continue }
            let rich = text.attributedSubstring(from: NSRange(location: offset, length: value.utf16.count))
            let content = InlineMarkdown.encode(rich).replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "\u{2028}", with: "<br>").replacingOccurrences(of: "|", with: "\\|")
            if let previous = rows[row]?[column] { rows[row, default: [:]][column] = previous + "<br>" + content }
            else { rows[row, default: [:]][column] = content }
        }
        let attrs = text.length > 0 ? text.attributes(at: 0, effectiveRange: nil) : [:]
        var lines = rows.keys.sorted().map { row in
            "| " + (rows[row] ?? [:]).keys.sorted().map { rows[row]?[$0] ?? "" }.joined(separator: " | ") + " |"
        }
        if !lines.isEmpty { lines.insert(attrs[.noteTableSeparator] as? String ?? "| --- | --- |", at: 1) }
        let canonical = lines.joined(separator: "\n")
        if preserveSource, canonical == attrs[.noteTableCanonical] as? String,
           let original = attrs[.noteTableSource] as? String { return original }
        return canonical
    }
}
