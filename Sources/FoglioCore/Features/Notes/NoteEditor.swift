import SwiftUI
import AppKit

/// Title, meta row, formatting toolbar and the block stack (:165-276).
struct NoteEditor: View {
    @Bindable var state: AppState
    let store: Store
    let note: Note
    /// Asks the list to confirm and carry out the delete — it owns both the
    /// dialog and the question of what gets selected next.
    let onDelete: () -> Void

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
        // Same reasoning as `blocks`: computed once here rather than per row.
        let numbers = Markdown.ordinals(of: blocks)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(blockCount: blocks.count)
                toolbar(blocks: blocks)
                blockStack(blocks, numbers: numbers)
            }
        }
        .onChange(of: state.activeBlock, initial: true) { _, index in
            guard let index, index < blocks.count else { return }
            draft = editableText(at: index, in: blocks)
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

            HStack(alignment: .top, spacing: 8) {
                // Wraps for the same reason the toolbar below does: the folder
                // chip, the meta and the pin menu want ~440pt, and the editor
                // pane is only ~380pt wide at the window's 900pt minimum.
                FlowLayout(spacing: 8, lineSpacing: 6) {
                    folderMenu
                    Text("edited \(Relative.label(for: note.updatedAt)) · \(blockCount) blocks")
                        .font(Typo.sans(11.5))
                        .foregroundStyle(theme.muted)
                        .fixedSize()
                    pinMenu
                }
                Spacer(minLength: 8)
                deleteButton
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

    private var deleteButton: some View {
        Button(action: onDelete) {
            HStack(spacing: 6) {
                IconView(icon: .trash, size: 12, lineWidth: 1.6)
                Text("Delete").font(Typo.sans(11))
            }
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .hoverHighlight(theme, cornerRadius: 6)
        }
        .buttonStyle(.flat)
        .help("Delete this note")
    }

    /// The note's folder, and the way to change it — the meta line used to
    /// name the folder in passing, which told you where a note lived but gave
    /// you no way to move it.
    private var folderMenu: some View {
        Menu {
            ForEach(store.folders) { folder in
                Button(folder.label) { store.move(noteIds: [note.id], to: folder) }
                    // The one it is already in: shown, so the list is the whole
                    // set of folders, but not offered as a move.
                    .disabled(folder == note.folder)
            }
        } label: {
            HStack(spacing: 6) {
                IconView(icon: .folder, size: 11, lineWidth: 1.8)
                Text(note.folder.label).font(Typo.sans(11)).lineLimit(1)
            }
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move this note to another folder")
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
        case bullet = "Bullet", numbered = "Numbered"
        case checklist = "Checklist", code = "Code"

        static func of(_ block: Block) -> Format? {
            switch block {
            case .h1: .title
            case .h2: .heading
            case .paragraph: .body
            case .listItem: .bullet
            case .orderedItem: .numbered
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
        HStack(alignment: .top, spacing: 8) {
            // Wraps rather than truncates. The six buttons plus the tag want
            // ~500pt, and the editor pane is only ~380pt wide at the window's
            // 900pt minimum — as a plain HStack the labels got clipped there.
            FlowLayout(spacing: 4, lineSpacing: 4) {
                // No pre-selected state: a button only lights up on hover or
                // press, so nothing looks chosen that you didn't choose. What
                // block you're in is reported by the quiet tag on the right.
                toolbarButton("Heading", hint: "Heading — or type ## ") {
                    convert(to: .h2(""), blocks: blocks)
                }
                toolbarButton("Body", hint: "Plain paragraph") {
                    convert(to: .paragraph(""), blocks: blocks)
                }
                toolbarButton("Bullets", hint: "Bulleted list — or type - ") {
                    convert(to: .listItem(""), blocks: blocks)
                }
                toolbarButton("Numbered", hint: "Numbered list — or type 1. ") {
                    convert(to: .orderedItem(""), blocks: blocks)
                }
                toolbarButton("Checklist", hint: "Checklist — or type - [ ] ") {
                    convert(to: .todo(text: "", checked: false), blocks: blocks)
                }
                toolbarButton("Code", hint: "Code block — or type ``` ") {
                    insert(.code(language: "go", text: "// code"), blocks: blocks)
                }
                moreMenu(blocks: blocks)
            }

            Spacer(minLength: 8)

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
                Text("## · - · 1. · - [ ] · ```")
                    .font(Typo.mono(10.5))
                    .foregroundStyle(theme.muted)
                    .fixedSize()
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

    private func blockStack(_ blocks: [Block], numbers: [Int?]) -> some View {
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
                        ordinal: numbers[index],
                        alreadySent: isSent(block),
                        onEdit: { beginEditing(index, blocks: blocks) },
                        onToggleCheck: { toggleCheck(at: index) },
                        onSendToTasks: { sendToTasks(block) },
                        onOpenLink: openLink
                    )
                }
            }

            // Only offer "Type to continue…" when there isn't already an empty
            // block to type into. Showing both stacked an invisible empty row on
            // top of the placeholder — the gap under the toolbar — and clicking
            // it appended a *second* blank line rather than using the first.
            if needsPlaceholder(blocks) {
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
        }
        .padding(.horizontal, 26)
        .padding(.top, 20).padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard state.activeBlock == nil else { return }
            if needsPlaceholder(blocks) {
                appendBlock(count: blocks.count)
            } else {
                beginEditing(blocks.count - 1, blocks: blocks)
            }
        }
    }

    /// True when the document doesn't already end in somewhere to type.
    ///
    /// An empty trailing paragraph *is* the place to continue, so showing the
    /// placeholder as well stacked an invisible row on top of it — the gap under
    /// the toolbar — and clicking it appended a second blank line instead of
    /// using the first.
    static func needsPlaceholder(_ blocks: [Block]) -> Bool {
        guard let last = blocks.last else { return true }
        if case .paragraph(let text) = last { return !text.isEmpty }
        return true
    }

    private func needsPlaceholder(_ blocks: [Block]) -> Bool {
        Self.needsPlaceholder(blocks)
    }

    // MARK: - Editing lifecycle

    private func beginEditing(_ index: Int, blocks: [Block]) {
        // Commit whatever block we were in before moving.
        commitDraft(blocks)
        draft = editableText(at: index, in: blocks)
        state.activeBlock = index
    }

    /// The raw markdown for one block, with a numbered item showing the number
    /// it actually carries. Only numbered items pay for the count, and only
    /// when a block is opened — not on every render.
    private func editableText(at index: Int, in blocks: [Block]) -> String {
        guard blocks.indices.contains(index) else { return "" }
        guard case .orderedItem = blocks[index] else {
            return Markdown.editableText(for: blocks[index])
        }
        return Markdown.editableText(for: blocks[index], ordinal: Markdown.ordinals(of: blocks)[index])
    }

    /// Writes the draft back into the note. The only path by which typed text
    /// reaches the store.
    private func commitDraft(_ blocks: [Block]) {
        guard let index = state.activeBlock, index < blocks.count else { return }
        guard editableText(at: index, in: blocks) != draft else { return }
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
        var arr = note.blocks
        transform(&arr)
        commit(arr)
    }

    /// Replaces the active block with the same text in a new form (`convert`, :795).
    private func convert(to kind: Block, blocks: [Block]) {
        guard let index = state.activeBlock, index < blocks.count else {
            insert(kind, blocks: blocks)
            return
        }
        // Use what's being typed, not the last committed value.
        let text = Markdown.applyEdit(draft, to: blocks[index]).plainText
        var updated = blocks
        updated[index] = kindWith(kind, text)
        commit(updated)
        // Seeded from the updated document, so turning the third item of a run
        // into a numbered item shows "3." rather than a misleading "1.".
        draft = editableText(at: index, in: updated)
    }

    private func kindWith(_ kind: Block, _ text: String) -> Block {
        switch kind {
        case .h1: .h1(text)
        case .h2: .h2(text)
        case .listItem: .listItem(text)
        case .orderedItem: .orderedItem(text)
        case .todo: .todo(text: text, checked: false)
        default: .paragraph(text)
        }
    }

    /// Inserts after the active block, or appends (`insert`, :778).
    private func insert(_ block: Block, blocks: [Block]) {
        commitDraft(blocks)
        let index = state.activeBlock.map { $0 + 1 } ?? blocks.count
        moveFocus {
            var updated = note.blocks
            let at = min(index, updated.count)
            updated.insert(block, at: at)
            commit(updated)
            draft = editableText(at: at, in: updated)
            state.activeBlock = index
        }
    }

    /// Return: carry the list on, or end it.
    ///
    /// A list that doesn't continue itself isn't usable — you'd click "Bullets"
    /// once per line. And an empty item is how everyone signals they're done
    /// with the list, so Return there turns it back into a paragraph instead of
    /// adding another empty bullet you then have to delete.
    private func splitBlock(at index: Int, blocks: [Block]) {
        moveFocus {
            var arr = blocks
            let edited = Markdown.applyEdit(draft, to: arr[index])

            guard let next = Self.continuation(after: edited) else {
                arr[index] = .paragraph("")
                commit(arr)
                draft = ""
                state.activeBlock = index
                return
            }

            arr[index] = edited
            arr.insert(next, at: index + 1)
            commit(arr)

            draft = editableText(at: index + 1, in: arr)
            state.activeBlock = index + 1
        }
    }

    /// The block Return should add after `block`, or nil when it should end a
    /// list instead — which is what an empty item asks for.
    static func continuation(after block: Block) -> Block? {
        if block.isListItem && block.plainText.isEmpty { return nil }
        return block.continuation
    }

    private func commit(_ blocks: [Block]) {
        var updated = note
        updated.blocks = blocks
        store.upsert(updated)
    }

    private func deleteBlock(at index: Int, blocks: [Block]) {
        guard blocks.count > 1 else { return }
        moveFocus {
            var updated = blocks
            updated.remove(at: index)
            commit(updated)

            // Seeded from the document *after* the removal. Backspacing out of
            // an empty first block used to seed the draft from the block that
            // had just been deleted — so the editor showed "" over whatever now
            // sat at index 0, and blurring committed that "" over its text.
            let target = max(0, index - 1)
            draft = editableText(at: target, in: updated)
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
