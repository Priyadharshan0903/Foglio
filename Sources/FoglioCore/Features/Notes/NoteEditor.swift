import SwiftUI
import AppKit

struct NoteEditor: View {
    @Bindable var state: AppState
    let store: Store
    let note: Note
    let onDelete: () -> Void

    @State private var controller = NoteEditorController()
    @FocusState private var titleFocused: Bool
    private var theme: Theme { state.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if state.sourceMode {
                toolbar
                ScrollView {
                    RawTextEditor(
                        text: bodyBinding, font: Typo.monoNSFont(13), textColor: NSColor(theme.text),
                        allowsNewlines: true, lineSpacing: 5, caretAtEnd: false, minHeight: 420,
                        escapeResignsFocus: true, onEnter: {}, onBackspaceWhenEmpty: {},
                        onEscape: { store.flushPendingSaves() }, onBlur: { store.flushPendingSaves() }
                    )
                    .padding(28)
                }
            } else {
                RichTextEditor(id: note.id, markdown: bodyBinding, controller: controller,
                               theme: theme, baseURL: store.root,
                               requestFocus: state.activeBlock != nil && !note.body.isEmpty,
                               onBlur: { store.flushPendingSaves() })
            }
        }
        .background(theme.surface)
        .onAppear {
            if note.title.isEmpty && note.body.isEmpty { titleFocused = true }
        }
        .onDisappear { store.flushPendingSaves() }
        .onChange(of: state.sourceMode) { _, _ in store.flushPendingSaves() }
    }

    private var bodyBinding: Binding<String> {
        Binding(get: { store.note(id: note.id)?.body ?? note.body },
                set: { store.updateNoteBody(id: note.id, body: $0) })
    }

    private var titleBinding: Binding<String> {
        Binding(get: { store.note(id: note.id)?.title ?? note.title },
                set: { title in
                    guard var current = store.note(id: note.id) else { return }
                    current.title = title
                    store.upsert(current, debounced: true)
                })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(store.folders) { folder in
                        Button(folder.label) { store.move(noteIds: [note.id], to: folder) }
                            .disabled(folder == note.folder)
                    }
                } label: {
                    Label(note.folder.label, systemImage: "folder")
                        .font(Typo.sans(11.5)).foregroundStyle(theme.muted)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Move to folder")
                Spacer()
                Text("Edited \(Relative.label(for: note.updatedAt))")
                    .font(Typo.sans(11)).foregroundStyle(theme.muted)
                moreMenu
            }
            TextField("Untitled note", text: titleBinding, axis: .vertical)
                .textFieldStyle(.plain).font(Typo.sans(26, .semibold))
                .foregroundStyle(theme.text).lineLimit(1...3)
                .focused($titleFocused)
                .onSubmit { controller.textView?.window?.makeFirstResponder(controller.textView) }
            if let pin = note.pin {
                Label("Linked to \(pin)", systemImage: "link")
                    .font(Typo.sans(11)).foregroundStyle(theme.muted)
            }
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 18)
    }

    private var toolbar: some View {
        HStack {
            Text("Markdown editing").font(Typo.sans(12)).foregroundStyle(theme.muted)
            Spacer()
            Button("Done") { state.sourceMode = false }
                .buttonStyle(.flat).foregroundStyle(theme.accentDeep)
        }
        .padding(.horizontal, 28).padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
    }

    private var moreMenu: some View {
        Menu {
            Button(state.sourceMode ? "Return to writing" : "Edit as Markdown") { state.sourceMode.toggle() }
            Menu("Link to a task or goal") {
                Button("None") { setPin(nil) }
                ForEach(store.pinTargets, id: \.self) { target in
                    Button(target) { setPin(target) }
                }
            }
            Button("Add checklist items to Tasks") { addChecklistTasks() }
                .disabled(!note.blocks.contains { block in
                    if case .todo(let text, false) = block { return !text.isEmpty && !store.hasTask(labelled: text) }
                    return false
                })
            Divider()
            Button("Move to Trash…", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 16)).foregroundStyle(theme.muted)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Note options")
    }

    private func setPin(_ pin: String?) {
        guard var current = store.note(id: note.id) else { return }
        current.pin = pin
        store.upsert(current)
    }

    private func addChecklistTasks() {
        for block in note.blocks {
            guard case .todo(let text, false) = block, !text.isEmpty, !store.hasTask(labelled: text) else { continue }
            store.addTask(TaskItem(label: text, lane: store.defaultLane,
                                  meta: "From \(note.title.isEmpty ? "Untitled note" : note.title)"))
        }
    }
}
