import SwiftUI

/// One rendered (not being edited) block (Day Log.dc.html:209-271).
struct BlockView: View {
    let block: Block
    let theme: Theme
    /// True when a task with this todo's label already exists.
    var alreadySent: Bool = false
    var onEdit: () -> Void
    var onToggleCheck: () -> Void
    var onSendToTasks: () -> Void
    var onOpenLink: (String) -> Void

    var body: some View {
        switch block {
        case .h1(let text):
            Text(text)
                .font(Typo.sans(20, .semibold))
                .kerning(-0.3)
                .foregroundStyle(theme.text)
                .padding(.top, 12).padding(.bottom, 5).padding(.horizontal, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)

        case .h2(let text):
            Text(text)
                .font(Typo.sans(15.5, .semibold))
                .foregroundStyle(theme.text)
                .padding(.top, 10).padding(.bottom, 4).padding(.horizontal, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)

        case .paragraph(let text):
            paragraph(text)

        case .listItem(let text):
            HStack(alignment: .top, spacing: 11) {
                Text("—").foregroundStyle(theme.muted)
                Text(text).foregroundStyle(theme.text)
            }
            .font(Typo.sans(14))
            .lineSpacing(9.5)
            .padding(.vertical, 4).padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

        case .todo(let text, let checked):
            todo(text: text, checked: checked)

        case .code(let language, let text):
            code(language: language, text: text)

        case .table(let rows):
            table(rows)

        case .image(let alt, _):
            VStack(spacing: 5) {
                Text(alt.isEmpty ? "Image" : alt)
                    .font(Typo.sans(12.5))
                    .foregroundStyle(theme.muted)
                Text("Drop an image or paste a screenshot")
                    .font(Typo.sans(11))
                    .foregroundStyle(theme.muted.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(30)
            .background(theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 1.5)
            )
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

        case .divider:
            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
                .padding(.vertical, 16).padding(.horizontal, 9)
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)
        }
    }

    // MARK: - Paragraph with [[wiki links]]

    private func paragraph(_ text: String) -> some View {
        let spans = WikiLink.spans(in: text)
        return HStack(spacing: 0) {
            // A single concatenated Text can't carry per-span tap targets, so
            // links become their own views and the rest flows as text.
            WrappingSpans(spans: spans, theme: theme, onOpenLink: onOpenLink)
        }
        .font(Typo.sans(14))
        .lineSpacing(9.5)
        .padding(.vertical, 5).padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }

    // MARK: - Todo

    private func todo(text: String, checked: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: onToggleCheck) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(checked ? theme.ok : .clear)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(checked ? theme.ok : theme.muted, lineWidth: 1.5)
                    if checked {
                        Text("✓").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.bg)
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.flat)
            .padding(.top, 3)

            StrikeText(
                text: text,
                struck: checked,
                font: Typo.sans(14),
                color: checked ? theme.muted : theme.text,
                strikeColor: theme.ok
            )
            .lineSpacing(8.4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

            Spacer(minLength: 8)

            Button(action: onSendToTasks) {
                Text(alreadySent ? "IN TASKS" : "→ TASK")
                    .font(Typo.sans(10))
                    .kerning(0.6)
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.flat)
            .disabled(alreadySent)
            .help(alreadySent ? "Already in the task lanes" : "Send to task lanes")
        }
        .padding(.vertical, 5).padding(.horizontal, 9)
    }

    // MARK: - Code

    private func code(language: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.uppercased())
                    .font(Typo.mono(10.5))
                    .kerning(1.05)
                    .foregroundStyle(theme.muted)
                Spacer()
                Button("edit", action: onEdit)
                    .buttonStyle(.flat)
                    .font(Typo.sans(10.5))
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.lineSoft).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 0) {
                        ForEach(Array(GoSyntax.tokenize(line).enumerated()), id: \.offset) { _, token in
                            Text(token.text)
                                .font(Typo.mono(12.5))
                                .foregroundStyle(color(for: token.role))
                                .fixedSize()
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 21, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
        }
        .background(theme.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
        .padding(.vertical, 9)
    }

    private func color(for role: TokenRole) -> Color {
        switch role {
        case .comment: theme.muted
        case .string: theme.ok
        case .number: theme.clay
        case .keyword: theme.accentDeep
        case .identifier: theme.text
        case .punctuation: theme.muted
        }
    }

    // MARK: - Table

    private func table(_ rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                HStack(spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(Typo.sans(12.5, rowIndex == 0 ? .semibold : .regular))
                            .foregroundStyle(rowIndex == 0 ? theme.text : theme.muted)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(rowIndex == 0 ? theme.field : theme.surface)
                .overlay(alignment: .top) {
                    if rowIndex > 0 {
                        Rectangle().fill(theme.lineSoft).frame(height: 1)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

/// Lays paragraph spans out inline, making `[[links]]` tappable (:218).
private struct WrappingSpans: View {
    let spans: [NoteSpan]
    let theme: Theme
    let onOpenLink: (String) -> Void

    var body: some View {
        // Plain paragraphs are the overwhelmingly common case and must wrap
        // properly, so they stay a single Text. Only mixed content pays the
        // cost of splitting into separate views.
        if spans.count == 1, case .text(let only) = spans[0] {
            Text(only)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            FlowLayout(spacing: 0) {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    switch span {
                    case .text(let t):
                        ForEach(Array(t.split(separator: " ", omittingEmptySubsequences: false).enumerated()), id: \.offset) { i, word in
                            Text(i == 0 ? String(word) : " " + String(word))
                                .foregroundStyle(theme.text)
                        }
                    case .link(let target):
                        Text(target)
                            .foregroundStyle(theme.accentDeep)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(theme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onTapGesture { onOpenLink(target) }
                    }
                }
            }
        }
    }
}
