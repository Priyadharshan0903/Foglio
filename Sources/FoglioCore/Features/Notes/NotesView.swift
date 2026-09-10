import SwiftUI

/// The Notes section: folders / list / editor (Day Log.dc.html:129-277).
struct NotesView: View {
    @Bindable var state: AppState
    let store: Store

    /// The notes a delete has been asked for but not yet confirmed.
    ///
    /// Still confirmed, though deleting is no longer destructive: it moves the
    /// note to the trash, where it keeps for ten days. The dialog stays
    /// because a note vanishing from the list is a surprise worth one click,
    /// not because it can't be undone. One list rather than one note, because
    /// the same dialog confirms a whole selection.
    @State private var pendingDeletion: [Note] = []

    /// The folder currently being named, or renamed — see `FolderEdit`.
    @State private var folderEdit: FolderEdit?
    @FocusState private var folderFieldFocused: Bool

    private var theme: Theme { state.theme }

    private var query: String {
        state.search.trimmingCharacters(in: .whitespaces)
    }

    private var visibleNotes: [Note] {
        store.notes
            .filter { state.folderFilter == nil || $0.folder == state.folderFilter }
            .filter { $0.matches(query) }
    }

    private var activeNote: Note? {
        if let id = state.activeNoteId, let found = store.note(id: id) { return found }
        return visibleNotes.first
    }

    var body: some View {
        HStack(spacing: 0) {
            folderPane
            Divider().overlay(theme.line)
            listPane
            Divider().overlay(theme.line)
            editorPane
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
            titleVisibility: .visible
        ) {
            Button(
                pendingDeletion.count == 1 ? "Move to Trash" : "Move \(pendingDeletion.count) Notes to Trash",
                role: .destructive
            ) {
                confirmDeletion()
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text(
                pendingDeletion.count == 1
                    ? "It stays in the trash for \(Store.trashRetentionDays) days, and can be put back until then."
                    : "They stay in the trash for \(Store.trashRetentionDays) days, and can be put back until then."
            )
        }
    }

    // MARK: - Deleting

    private var deletionTitle: String {
        guard let first = pendingDeletion.first else { return "" }
        if pendingDeletion.count == 1 {
            return "Move “\(title(of: first))” to the trash?"
        }
        return "Move \(pendingDeletion.count) notes to the trash?"
    }

    private func title(of note: Note) -> String {
        note.title.isEmpty ? "Untitled note" : note.title
    }

    private func confirmDeletion() {
        let ids = Set(pendingDeletion.map(\.id))

        // Selection is handed to a survivor *before* the notes go, so the
        // editor lands somewhere deliberate rather than falling back to
        // whatever happens to top the list.
        state.activeNoteId = Self.survivor(after: ids, in: visibleNotes, current: state.activeNoteId)
        state.activeBlock = nil
        store.trashNotes(ids: ids)

        state.noteSelection.subtract(ids)
        if state.noteSelection.isEmpty { state.selectingNotes = false }
        pendingDeletion = []
    }

    /// The nearest note that isn't being deleted: the first one after the last
    /// casualty, else the last one before it, else nothing left to show.
    ///
    /// Static and pure so the choice can be checked without a window.
    static func survivor(after ids: Set<UUID>, in visible: [Note], current: UUID?) -> UUID? {
        guard let last = visible.lastIndex(where: { ids.contains($0.id) }) else { return current }
        if let next = visible[visible.index(after: last)...].first(where: { !ids.contains($0.id) }) {
            return next.id
        }
        return visible[..<last].last { !ids.contains($0.id) }?.id
    }

    // MARK: - Folders

    /// The inline folder text field — one piece of state, because it is one
    /// control: `folder == nil` is naming a new folder, otherwise it is
    /// renaming that one.
    private struct FolderEdit: Equatable {
        var folder: Folder?
        var text: String
    }

    private var folderPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            newNoteButton

            HStack(spacing: 4) {
                Text("FOLDERS")
                    .font(Typo.sans(10))
                    .kerning(1.6)
                    .foregroundStyle(theme.muted)
                Spacer(minLength: 4)
                Button {
                    folderEdit = FolderEdit(folder: nil, text: "")
                    folderFieldFocused = true
                } label: {
                    IconView(icon: .capture, size: 12, lineWidth: 1.9)
                        .foregroundStyle(theme.muted)
                        .padding(3)
                        .hoverHighlight(theme, cornerRadius: 5)
                }
                .buttonStyle(.flat)
                .help("New folder")
            }
            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)

            // Scrolls because the list is no longer three fixed rows: enough
            // folders would otherwise push the pane past the bottom of the
            // window with no way to reach them.
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    folderList
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(width: 168)
        .frame(maxHeight: .infinity)
        .background(theme.surface)
    }

    @ViewBuilder
    private var folderList: some View {
        folderRow(nil, label: "All notes", icon: .all, count: store.notes.count)

        ForEach(store.folders) { folder in
            if folderEdit?.folder == folder {
                folderField(placeholder: folder.label)
            } else {
                folderRow(
                    folder,
                    label: folder.label,
                    icon: .folder,
                    count: store.notes.filter { $0.folder == folder }.count
                )
                .contextMenu {
                    Button("Rename…") {
                        folderEdit = FolderEdit(folder: folder, text: folder.rawValue)
                        folderFieldFocused = true
                    }
                    // Scratch is where the notes of a deleted folder land,
                    // so it is the one folder that has to stay.
                    if folder != .scratch {
                        Button("Delete Folder", role: .destructive) { deleteFolder(folder) }
                    }
                }
            }
        }

        // Naming a new folder: the field sits at the end of the list,
        // where the folder itself is about to appear.
        if let edit = folderEdit, edit.folder == nil {
            folderField(placeholder: "Folder name")
        }
    }

    private var newNoteButton: some View {
        Button {
            let note = store.newNote(in: state.folderFilter ?? .scratch)
            state.activeNoteId = note.id
            state.activeBlock = 0
            state.endNoteSelection()
        } label: {
            HStack(spacing: 8) {
                IconView(icon: .capture, size: 14, lineWidth: 2)
                Text("New note").font(Typo.sans(12.5, .semibold))
            }
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.flat)
        .padding(.bottom, 8)
        // Says where it will land, since a new note joins whichever folder is
        // showing rather than always going to Scratch.
        .help("New note in \(state.folderFilter?.label ?? Folder.scratch.label)")
    }

    private func folderField(placeholder: String) -> some View {
        TextField(placeholder, text: Binding(
            get: { folderEdit?.text ?? "" },
            set: { folderEdit?.text = $0 }
        ))
        .textFieldStyle(.plain)
        .font(Typo.sans(12.5))
        .foregroundStyle(theme.text)
        .focused($folderFieldFocused)
        // Focus is taken here rather than where the edit starts: the field
        // doesn't exist yet at that point, so a `@FocusState` set from the
        // button would land on nothing.
        .onAppear { folderFieldFocused = true }
        .onSubmit { commitFolderEdit() }
        // Escape abandons the name. Without this it would fall through to the
        // window, which reads Escape as "close" — a heavy answer to a typo.
        .onExitCommand { cancelFolderEdit() }
        // Clicking away is a cancel, not a commit: a half-typed name shouldn't
        // become a folder because focus moved.
        .onChange(of: folderFieldFocused) { _, focused in
            if !focused { folderEdit = nil }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }

    private func cancelFolderEdit() {
        folderEdit = nil
        folderFieldFocused = false
    }

    private func commitFolderEdit() {
        guard let edit = folderEdit else { return }
        if let existing = edit.folder {
            store.renameFolder(existing, to: edit.text)
            // Follow the rename, so the pane doesn't jump back to All notes.
            if state.folderFilter == existing { state.folderFilter = Folder(edit.text) }
        } else if let created = store.addFolder(named: edit.text) {
            state.folderFilter = created
        }
        folderEdit = nil
        folderFieldFocused = false
    }

    private func deleteFolder(_ folder: Folder) {
        if state.folderFilter == folder { state.folderFilter = nil }
        store.deleteFolder(folder)
    }

    private func folderRow(_ folder: Folder?, label: String, icon: Icon, count: Int) -> some View {
        let selected = state.folderFilter == folder
        return Button {
            state.folderFilter = folder
            // A selection made under one filter would act on notes you can no
            // longer see, so changing filter ends it.
            state.endNoteSelection()
        } label: {
            HStack(spacing: 9) {
                IconView(icon: icon, size: 14)
                Text(label).font(Typo.sans(12.5)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(Typo.mono(11)).foregroundStyle(theme.muted)
            }
            .foregroundStyle(selected ? theme.text : theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? theme.accentSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.flat)
        .modifier(FolderDrop(folder: folder, theme: theme) { ids in
            guard let folder else { return }
            store.move(noteIds: ids, to: folder)
        })
    }

    /// Notes dropped on a folder row are filed there. "All notes" isn't a
    /// folder, so it takes no drops.
    private struct FolderDrop: ViewModifier {
        let folder: Folder?
        let theme: Theme
        let onDrop: ([UUID]) -> Void

        @State private var targeted = false

        func body(content: Content) -> some View {
            guard folder != nil else { return AnyView(content) }
            return AnyView(
                content
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(targeted ? theme.accentSoft : .clear)
                    )
                    .dropDestination(for: String.self) { payload, _ in
                        let ids = payload.flatMap(NoteDrag.ids(from:))
                        guard !ids.isEmpty else { return false }
                        onDrop(ids)
                        return true
                    } isTargeted: { targeted = $0 }
            )
        }
    }

    // MARK: - Note list

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleNotes) { note in
                        noteRow(note)
                    }
                }
            }

            if state.selectingNotes {
                selectionBar
            }
        }
        .frame(width: 244)
        .frame(maxHeight: .infinity)
        .background(theme.bg)
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(query.isEmpty ? (state.folderFilter?.label ?? "All notes").uppercased() : "SEARCH RESULTS")
                .font(Typo.sans(10))
                .kerning(1.6)
                .foregroundStyle(theme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                if state.selectingNotes {
                    state.endNoteSelection()
                } else {
                    state.selectingNotes = true
                }
            } label: {
                Text(state.selectingNotes ? "DONE" : "SELECT")
                    .font(Typo.sans(10))
                    .kerning(0.9)
                    .foregroundStyle(state.selectingNotes ? theme.accentDeep : theme.muted)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .hoverHighlight(theme, cornerRadius: 5)
            }
            .buttonStyle(.flat)
            .help(state.selectingNotes ? "Leave selection (⎋)" : "Select several notes to move or delete")

            Text("\(visibleNotes.count)")
                .font(Typo.mono(11))
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
    }

    private var selectionBar: some View {
        let chosen = state.noteSelection

        return HStack(spacing: 8) {
            // The bar needs 213pt of the 216pt the list pane has, measured in
            // Geist at these sizes. So the count — the one part that can be
            // read from the ticks themselves — yields first, rather than the
            // Delete button losing its edge off the end of the pane.
            Text("\(chosen.count) selected")
                .font(Typo.sans(11.5))
                .foregroundStyle(theme.muted)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(chosen.count == visibleNotes.count ? "None" : "All") {
                state.noteSelection = chosen.count == visibleNotes.count
                    ? []
                    : Set(visibleNotes.map(\.id))
            }
            .buttonStyle(.flat)
            .font(Typo.sans(11.5))
            .foregroundStyle(theme.muted)
            .layoutPriority(1)

            Menu {
                ForEach(store.folders) { folder in
                    Button(folder.label) { store.move(noteIds: chosen, to: folder) }
                }
            } label: {
                Text("Move").font(Typo.sans(11.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(theme.muted)
            .layoutPriority(1)
            .disabled(chosen.isEmpty)

            Button {
                pendingDeletion = visibleNotes.filter { chosen.contains($0.id) }
            } label: {
                HStack(spacing: 5) {
                    IconView(icon: .trash, size: 12, lineWidth: 1.6)
                    Text("Trash").font(Typo.sans(11.5))
                }
                .foregroundStyle(chosen.isEmpty ? theme.muted : theme.clay)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .hoverHighlight(theme, cornerRadius: 6, active: !chosen.isEmpty)
            }
            .buttonStyle(.flat)
            .layoutPriority(1)
            .disabled(chosen.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    private func noteRow(_ note: Note) -> some View {
        let selected = note.id == activeNote?.id
        let ticked = state.noteSelection.contains(note.id)

        return Button {
            if state.selectingNotes {
                toggle(note)
            } else {
                state.activeNoteId = note.id
                state.activeBlock = nil
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if state.selectingNotes {
                    checkbox(ticked: ticked).padding(.top, 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(title(of: note))
                            .font(Typo.sans(13, .medium))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        if note.pin != nil {
                            IconView(icon: .pin, size: 12, lineWidth: 1.8)
                                .foregroundStyle(theme.accentDeep)
                        }
                        Spacer(minLength: 4)
                        Text(Relative.label(for: note.updatedAt))
                            .font(Typo.mono(10.5))
                            .foregroundStyle(theme.muted)
                    }
                    Text(note.snippet)
                        .font(Typo.sans(11.5))
                        .foregroundStyle(theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(selected: selected, ticked: ticked))
            .overlay(alignment: .top) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
        }
        .buttonStyle(.flat)
        .draggable(NoteDrag.payload(for: note, selection: state.noteSelection))
        .contextMenu { rowMenu(note) }
    }

    /// While selecting, a tick is what the row is saying; the editor's
    /// selection would otherwise read as a second, competing highlight.
    private func background(selected: Bool, ticked: Bool) -> Color {
        if state.selectingNotes { return ticked ? theme.accentSoft : .clear }
        return selected ? theme.accentSoft : .clear
    }

    private func checkbox(ticked: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(ticked ? theme.accentDeep : .clear)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(ticked ? theme.accentDeep : theme.muted, lineWidth: 1.5)
            if ticked {
                Text("✓").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.surface)
            }
        }
        .frame(width: 16, height: 16)
    }

    private func toggle(_ note: Note) {
        if state.noteSelection.contains(note.id) {
            state.noteSelection.remove(note.id)
        } else {
            state.noteSelection.insert(note.id)
        }
    }

    /// A right-click acts on the selection when the row is part of one, and on
    /// that row alone otherwise — clicking a note outside the selection to
    /// delete "it" should not take the selection with it.
    private func targets(of note: Note) -> [Note] {
        guard state.noteSelection.contains(note.id) else { return [note] }
        return visibleNotes.filter { state.noteSelection.contains($0.id) }
    }

    @ViewBuilder
    private func rowMenu(_ note: Note) -> some View {
        let chosen = targets(of: note)

        Menu("Move to") {
            ForEach(store.folders) { folder in
                Button(folder.label) { store.move(noteIds: chosen.map(\.id), to: folder) }
                    .disabled(chosen.allSatisfy { $0.folder == folder })
            }
        }
        Button(state.selectingNotes ? "Deselect All" : "Select…") {
            if state.selectingNotes {
                state.endNoteSelection()
            } else {
                state.selectingNotes = true
                state.noteSelection = [note.id]
            }
        }
        Divider()
        Button(chosen.count == 1 ? "Move to Trash…" : "Move \(chosen.count) Notes to Trash…", role: .destructive) {
            pendingDeletion = chosen
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorPane: some View {
        if let note = activeNote {
            NoteEditor(state: state, store: store, note: note, onDelete: { pendingDeletion = [note] })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.bg)
        } else {
            VStack {
                Text(query.isEmpty ? "No notes yet." : "Nothing matches “\(query)”.")
                    .font(Typo.sans(12.5))
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
        }
    }
}

/// What a dragged note row carries.
///
/// A plain string rather than a custom `Transferable`: both ends are this app,
/// and a string drops harmlessly into anything else. Dragging a note that is
/// part of a selection brings the whole selection, which is what dragging one
/// of several highlighted things means everywhere else.
enum NoteDrag {
    static func payload(for note: Note, selection: Set<UUID>) -> String {
        let ids = selection.contains(note.id) ? Array(selection) : [note.id]
        return ids.map(\.uuidString).joined(separator: " ")
    }

    static func ids(from payload: String) -> [UUID] {
        payload.split(separator: " ").compactMap { UUID(uuidString: String($0)) }
    }
}

/// "14:20" today, "Yesterday", a weekday inside the last week, else "3 Aug"
/// — matching the `updated` strings in the design's sample data (:647).
enum Relative {
    static func label(for date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            f.dateFormat = "EEE"
        } else {
            f.dateFormat = "d MMM"
        }
        return f.string(from: date)
    }
}
