import SwiftUI
import AppKit

/// Title, meta row, formatting toolbar and the block stack (:165-276).
struct NoteEditor: View {
    @Bindable var state: AppState
    let store: Store
    let note: Note

    /// The text of the block currently being edited.
    ///
    /// Deliberately local. Routing every keystroke through the store meant the
    /// binding could hand `updateNSView` a stale value and overwrite what you
    /// had just typed — which is how text went missing on blur. The store now
    /// only hears about the edit when you leave the block.
    @State private var draft: String = ""
    /// Set while we move focus ourselves (Return, Backspace) so the resulting
    /// blur doesn't immediately cancel the move.
    @State private var movingFocus = false

    private var theme: Theme { state.theme }

    var body: some View {
        // Parsed once per render. `note.blocks` re-parses the whole document on
        // every access, so reading it across the view tree was a real cost.
        let blocks = note.blocks

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(blockCount: blocks.count)
                toolbar(blocks: blocks)
                blockStack(blocks)
            }
        }
        .onChange(of: state.activeBlock, initial: true) { _, index in
            guard let index, index < blocks.count else { return }
            draft = Markdown.editableText(for: blocks[index])
        }
        .onChange(of: note.id) { _, _ in
            state.activeBlock = nil
        }
    }

    // MARK: - Header

    private func header(blockCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Untitled note", text: titleBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.sans(23, .semibold))
                .kerning(-0.35)
                .foregroundStyle(theme.text)
                .lineLimit(1...3)

            HStack(spacing: 10) {
                Text("\(note.folder.label) · edited \(Relative.label(for: note.updatedAt)) · \(blockCount) blocks")
                    .font(Typo.sans(11.5))
                    .foregroundStyle(theme.muted)
                pinMenu
                Spacer()
            }
            .padding(.top, 9)
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { note.title },
            set: { newTitle in
                var updated = note
                updated.title = newTitle
                // Debounced: the filename tracks the title, so writing per
                // keystroke churned one file per character typed.
                store.upsert(updated, debounced: true)
            }
        )
    }

    private var pinMenu: some View {
        Menu {
            Button("Not pinned") { setPin(nil) }
            Divider()
            ForEach(store.pinTargets, id: \.self) { target in
                Button(target) { setPin(target) }
            }
        } label: {
            HStack(spacing: 6) {
                IconView(icon: .pin, size: 11, lineWidth: 1.8)
                Text(note.pin.map { "Pinned to \($0)" } ?? "Pin to a task or milestone")
                    .font(Typo.sans(11))
                    .lineLimit(1)
            }
            .foregroundStyle(note.pin != nil ? theme.accentDeep : theme.muted)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(note.pin != nil ? theme.accentSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func setPin(_ pin: String?) {
        var updated = note
        updated.pin = pin
        store.upsert(updated)
    }

    // MARK: - Toolbar

    private enum Format: String {
        case title = "Title", heading = "Heading", body = "Body"
        case checklist = "Checklist", code = "Code"

        static func of(_ block: Block) -> Format? {
            switch block {
            case .h1: .title
            case .h2: .heading
            case .paragraph: .body
            case .todo: .checklist
            case .code: .code
            default: nil
            }
        }
    }

    private func currentFormat(_ blocks: [Block]) -> Format? {
        guard let index = state.activeBlock, index < blocks.count else { return nil }
        return Format.of(blocks[index])
    }

    private func toolbar(blocks: [Block]) -> some View {
        HStack(spacing: 4) {
            // No pre-selected state: a button only lights up on hover or press,
            // so nothing looks chosen that you didn't choose. What block you're
            // in is reported by the quiet tag on the right instead.
            toolbarButton("Heading", hint: "Heading — or type ## ") {
                convert(to: .h2(""), blocks: blocks)
            }
            toolbarButton("Body", hint: "Plain paragraph") {
                convert(to: .paragraph(""), blocks: blocks)
            }
            toolbarButton("Checklist", hint: "Checklist — or type - [ ] ") {
                convert(to: .todo(text: "", checked: false), blocks: blocks)
            }
            toolbarButton("Code", hint: "Code block — or type ``` ") {
                insert(.code(language: "go", text: "// code"), blocks: blocks)
            }
            moreMenu(blocks: blocks)

            Spacer()

            if let format = currentFormat(blocks) {
                Text(format.rawValue)
                    .font(Typo.sans(10.5, .medium))
                    .kerning(0.4)
                    .foregroundStyle(theme.accentDeep)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(theme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .help("The block you're editing")
            } else {
                Text("## · - [ ] · ```")
                    .font(Typo.mono(10.5))
                    .foregroundStyle(theme.muted)
                    .help("Markdown shortcuts you can type directly")
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 10)
        .background(theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .padding(.top, 14)
    }

    private func toolbarButton(_ label: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typo.sans(11.5, .medium))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .hoverHighlight(theme, cornerRadius: 5)
        }
        .buttonStyle(.flat)
        .help(hint)
    }

    private func moreMenu(blocks: [Block]) -> some View {
        Menu {
            Button("Title") { convert(to: .h1(""), blocks: blocks) }
            Button("Table") {
                insert(.table(rows: [["Column", "Column", "Column"], ["value", "value", "value"]]), blocks: blocks)
            }
            Button("Image") { insert(.image(alt: "New image", path: ""), blocks: blocks) }
            Button("Note link") { insert(.paragraph("See [[Scratchpad]]"), blocks: blocks) }
            Button("Divider") { insert(.divider, blocks: blocks) }
        } label: {
            HStack(spacing: 4) {
                Text("More").font(Typo.sans(11.5, .medium))
                Text("▾").font(.system(size: 8))
            }
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .hoverHighlight(theme, cornerRadius: 5)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Blocks

    private func blockStack(_ blocks: [Block]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if state.activeBlock == index {
                    RawTextEditor(
                        text: $draft,
                        font: block.isMultiline
                            ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                            : NSFont.systemFont(ofSize: 14),
                        textColor: NSColor(theme.text),
                        allowsNewlines: block.isMultiline,
                        onEnter: { splitBlock(at: index, blocks: blocks) },
                        onBackspaceWhenEmpty: { deleteBlock(at: index, blocks: blocks) },
                        onEscape: { finishEditing(blocks) },
                        onBlur: { if !movingFocus { finishEditing(blocks) } }
                    )
                    .id(index) // fresh editor per block, so focus lands correctly
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(theme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    BlockView(
                        block: block,
                        theme: theme,
                        alreadySent: isSent(block),
                        onEdit: { beginEditing(index, blocks: blocks) },
                        onToggleCheck: { toggleCheck(at: index) },
                        onSendToTasks: { sendToTasks(block) },
                        onOpenLink: openLink
                    )
                }
            }

            Button {
                appendBlock(count: blocks.count)
            } label: {
                Text("Type to continue…")
                    .font(Typo.sans(14))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, 9).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.flat)
        }
        .padding(.horizontal, 26)
        .padding(.top, 20).padding(.bottom, 34)
    }

    // MARK: - Editing lifecycle

    private func beginEditing(_ index: Int, blocks: [Block]) {
        // Commit whatever block we were in before moving.
        commitDraft(blocks)
        draft = Markdown.editableText(for: blocks[index])
        state.activeBlock = index
    }

    /// Writes the draft back into the note. The only path by which typed text
    /// reaches the store.
    private func commitDraft(_ blocks: [Block]) {
        guard let index = state.activeBlock, index < blocks.count else { return }
        guard Markdown.editableText(for: blocks[index]) != draft else { return }
        mutate { $0[index] = Markdown.applyEdit(draft, to: $0[index]) }
    }

    private func finishEditing(_ blocks: [Block]) {
        commitDraft(blocks)
        state.activeBlock = nil
        store.flushPendingSaves()
    }

    /// Guards a focus move we make ourselves against the blur it causes.
    private func moveFocus(_ body: () -> Void) {
        movingFocus = true
        body()
        DispatchQueue.main.async { movingFocus = false }
    }

    // MARK: - Block operations

    private func mutate(_ transform: (inout [Block]) -> Void) {
        var updated = note
        var arr = updated.blocks
        transform(&arr)
        updated.blocks = arr
        store.upsert(updated)
    }

    /// Replaces the active block with the same text in a new form (`convert`, :795).
    private func convert(to kind: Block, blocks: [Block]) {
        guard let index = state.activeBlock, index < blocks.count else {
            insert(kind, blocks: blocks)
            return
        }
        // Use what's being typed, not the last committed value.
        let text = Markdown.applyEdit(draft, to: blocks[index]).plainText
        let converted = kindWith(kind, text)
        mutate { $0[index] = converted }
        draft = Markdown.editableText(for: converted)
    }

    private func kindWith(_ kind: Block, _ text: String) -> Block {
        switch kind {
        case .h1: .h1(text)
        case .h2: .h2(text)
        case .todo: .todo(text: text, checked: false)
        default: .paragraph(text)
        }
    }

    /// Inserts after the active block, or appends (`insert`, :778).
    private func insert(_ block: Block, blocks: [Block]) {
        commitDraft(blocks)
        let index = state.activeBlock.map { $0 + 1 } ?? blocks.count
        moveFocus {
            mutate { $0.insert(block, at: min(index, $0.count)) }
            draft = Markdown.editableText(for: block)
            state.activeBlock = index
        }
    }

    private func splitBlock(at index: Int, blocks: [Block]) {
        moveFocus {
            var arr = blocks
            arr[index] = Markdown.applyEdit(draft, to: arr[index])
            arr.insert(.paragraph(""), at: index + 1)
            var updated = note
            updated.blocks = arr
            store.upsert(updated)

            draft = ""
            state.activeBlock = index + 1
        }
    }

    private func deleteBlock(at index: Int, blocks: [Block]) {
        guard blocks.count > 1 else { return }
        moveFocus {
            mutate { $0.remove(at: index) }
            let target = max(0, index - 1)
            draft = target < blocks.count ? Markdown.editableText(for: blocks[target]) : ""
            state.activeBlock = target
        }
    }

    private func appendBlock(count: Int) {
        moveFocus {
            mutate { $0.append(.paragraph("")) }
            draft = ""
            state.activeBlock = count
        }
    }

    private func toggleCheck(at index: Int) {
        mutate { arr in
            if case .todo(let text, let checked) = arr[index] {
                arr[index] = .todo(text: text, checked: !checked)
            }
        }
    }

    private func isSent(_ block: Block) -> Bool {
        guard case .todo(let text, _) = block else { return false }
        return store.hasTask(labelled: text)
    }

    /// `addTaskFromTodo` (:775).
    private func sendToTasks(_ block: Block) {
        guard case .todo(let text, _) = block, !store.hasTask(labelled: text) else { return }
        store.addTask(TaskItem(label: text, lane: .priority, meta: "From \(note.title)"))
    }

    private func openLink(_ target: String) {
        guard let title = WikiLink.resolve(target, in: store.notes.map(\.title)),
              let match = store.notes.first(where: { $0.title == title })
        else { return }
        state.activeNoteId = match.id
        state.activeBlock = nil
    }
}
