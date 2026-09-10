import SwiftUI

/// The task board: one column per lane with drag between them, plus today's
/// completions (Day Log.dc.html:312-375).
///
/// The design drew three fixed columns. They are now `store.lanes` — a list you
/// can add to, rename, reorder and delete — so everything that used to be a
/// property of a `Lane` case (its position, its accent, whether it exists at
/// all) is a property of that list instead.
struct TasksView: View {
    @Bindable var state: AppState
    let store: Store

    /// Tasks mid-strike: checked, but not yet committed as done. The design
    /// holds this for 520ms so the strike animation can play out before the
    /// row disappears into "Completed today" (:806).
    @State private var striking: Set<UUID> = []

    /// The lane currently being named, or renamed — see `LaneEdit`.
    @State private var laneEdit: LaneEdit?
    @FocusState private var laneFieldFocused: Bool

    /// The task row currently open for editing — see `TaskEdit`.
    @State private var taskEdit: TaskEdit?
    @FocusState private var taskField: TaskField?

    /// The lane a delete has been asked for but not yet confirmed. Deleting a
    /// column tips every task in it into another lane, which is not something
    /// to do on a stray menu click.
    @State private var pendingLaneDeletion: Lane?

    private var theme: Theme { state.theme }

    /// The header search box claims to cover "notes, tasks, log". The design
    /// only ever filtered notes (:900); here it filters each section it names.
    private var query: String { state.search.trimmingCharacters(in: .whitespaces) }

    private func matching(_ tasks: [TaskItem]) -> [TaskItem] {
        guard !query.isEmpty else { return tasks }
        return tasks.filter {
            ($0.label + " " + $0.meta).lowercased().contains(query.lowercased())
        }
    }

    private var open: [TaskItem] { matching(store.tasks.filter { !$0.done }) }
    private var done: [TaskItem] { matching(store.tasks.filter(\.done)) }

    /// The lane the add row files into, kept honest against the board: the
    /// remembered choice survives in `AppState` across launches, and the lane
    /// it names may have been deleted since.
    private var draftLane: Lane {
        store.lanes.contains(state.draftLane) ? state.draftLane : store.defaultLane
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                addRow
                lanes
                completedToday
            }
            .padding(.horizontal, 32)
            .padding(.top, 26).padding(.bottom, 40)
            // A click anywhere on the board that isn't a control commits an
            // open row. AppKit keeps first responder on a text field when you
            // click empty space, so `taskField` never goes nil by itself —
            // without this the only blur that saved was one that moved the
            // caret to some *other* field, like the search box.
            //
            // Safe as a catch-all: children resolve their own clicks first (a
            // row's double-click still opens it), and committing with nothing
            // open does nothing.
            .contentShape(Rectangle())
            .onTapGesture { commitTaskEdit() }
        }
        .background(theme.bg)
        // Leaving Tasks entirely is a blur too — the section is swapped out of
        // a `switch`, so an open row would otherwise vanish with its edit.
        .onDisappear { commitTaskEdit() }
        .confirmationDialog(
            pendingLaneDeletion.map { "Delete the \($0.label) lane?" } ?? "",
            isPresented: Binding(
                get: { pendingLaneDeletion != nil },
                set: { if !$0 { pendingLaneDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Lane", role: .destructive) {
                if let lane = pendingLaneDeletion { store.deleteLane(lane) }
                pendingLaneDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingLaneDeletion = nil }
        } message: {
            Text(deletionMessage)
        }
    }

    /// Says where the tasks go, because they aren't deleted with the column —
    /// and says nothing about tasks when there are none to move.
    private var deletionMessage: String {
        guard let lane = pendingLaneDeletion else { return "" }
        let count = store.tasks.filter { $0.lane == lane }.count
        guard count > 0 else { return "The column is removed from the board." }
        let noun = count == 1 ? "task" : "tasks"
        let destination = store.lanes.first { $0 != lane } ?? store.defaultLane
        return "Its \(count) \(noun) move to \(destination.label). Nothing is deleted."
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Tasks")
                .font(Typo.sans(19, .semibold))
                .kerning(-0.3)
                .foregroundStyle(theme.text)
            Text("drag a row between lanes, or a lane to reorder")
                .font(Typo.sans(12))
                .foregroundStyle(theme.muted)
            Spacer()
            HStack(spacing: 12) {
                newLaneButton
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.line).frame(width: 130, height: 3)
                    Capsule().fill(theme.accent).frame(width: 130 * donePercent, height: 3)
                }
                Text("\(done.count)/\(store.tasks.count)")
                    .font(Typo.mono(11.5))
                    .foregroundStyle(theme.muted)
            }
        }
    }

    private var newLaneButton: some View {
        Button {
            commitTaskEdit()
            laneEdit = LaneEdit(lane: nil, text: "")
            laneFieldFocused = true
        } label: {
            HStack(spacing: 5) {
                IconView(icon: .capture, size: 11, lineWidth: 1.9)
                Text("Lane").font(Typo.sans(11.5, .medium))
            }
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .hoverHighlight(theme, cornerRadius: 6)
        }
        .buttonStyle(.flat)
        .help("New lane")
    }

    private var donePercent: CGFloat {
        guard !store.tasks.isEmpty else { return 0 }
        return CGFloat(done.count) / CGFloat(store.tasks.count)
    }

    // MARK: - Add row

    /// The lane chips sit under the field rather than beside it, and flow onto
    /// as many lines as they need: the design's three abbreviations fitted on
    /// one row, but a board can now carry any number of lanes with names long
    /// enough that "BLO" wouldn't tell two of them apart.
    private var addRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("Add to \(draftLane.label)…", text: $state.draft)
                .textFieldStyle(.plain)
                .font(Typo.sans(13.5))
                .foregroundStyle(theme.text)
                .onSubmit(addDraft)

            FlowLayout(spacing: 4, lineSpacing: 4) {
                ForEach(store.lanes) { lane in
                    let selected = draftLane == lane
                    Button { state.draftLane = lane } label: {
                        Text(lane.label)
                            .font(Typo.sans(10.5, .medium))
                            .kerning(0.42)
                            .lineLimit(1)
                            .foregroundStyle(selected ? theme.onAccent : theme.muted)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(selected ? theme.accent : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.flat)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: 520, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
        .padding(.top, 18)
    }

    private func addDraft() {
        let label = state.draft.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        let lane = draftLane
        store.addTask(TaskItem(
            label: label,
            lane: lane,
            meta: lane == .delegate ? "Follow up" : ""
        ))
        state.draft = ""
    }

    // MARK: - Lanes

    private var lanes: some View {
        HStack(alignment: .top, spacing: 30) {
            ForEach(Array(store.lanes.enumerated()), id: \.element.id) { index, lane in
                laneColumn(lane, at: index)
            }

            // Naming a new lane: the field stands where the column itself is
            // about to appear, at the end of the board.
            if let edit = laneEdit, edit.lane == nil {
                newLaneColumn
            }
        }
        .padding(.top, 28)
    }

    private func laneColumn(_ lane: Lane, at index: Int) -> some View {
        let items = open.filter { $0.lane == lane }
        // The first column is the urgent end of the board, so it wears the
        // accent — a property of where a lane sits now, not of which lane it
        // is, since the order is the user's to choose.
        let leading = index == 0
        return LaneDropTarget(theme: theme) { isTargeted in
            VStack(alignment: .leading, spacing: 0) {
                // Only the header becomes a field while renaming: the tasks
                // below are what tell you which column you're renaming, so
                // swapping out the whole column would hide the answer.
                if laneEdit?.lane == lane {
                    laneNameField(placeholder: lane.label)
                        .padding(.vertical, 4)
                } else {
                    laneHeader(lane, at: index, count: items.count, leading: leading)
                }

                if items.isEmpty {
                    Text(lane.emptyText)
                        .font(Typo.sans(12))
                        .foregroundStyle(theme.muted)
                        .padding(.vertical, 14).padding(.horizontal, 2)
                } else {
                    ForEach(items) { task in
                        taskRow(task, in: lane)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 150, alignment: .top)
            .padding(.horizontal, 8).padding(.bottom, 8)
            .background(isTargeted ? theme.accentSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        } onDrop: { payload in
            switch payload {
            case .task(let id):
                store.move(taskId: id, to: lane)
                return true
            case .lane(let draggedId):
                // Dropping a header on a column means "sit where that one
                // sits", so the dragged lane takes this one's index.
                guard let dragged = store.lanes.first(where: { $0.id == draggedId }),
                      dragged != lane
                else { return false }
                store.moveLane(dragged, to: index)
                return true
            }
        }
    }

    private func laneHeader(_ lane: Lane, at index: Int, count: Int, leading: Bool) -> some View {
        HStack(spacing: 8) {
            Text(lane.label.uppercased())
                .font(Typo.sans(11, .semibold))
                .kerning(1.32)
                .lineLimit(1)
                .foregroundStyle(leading ? theme.text : theme.muted)
            Spacer()
            Text("\(count)")
                .font(Typo.mono(11.5))
                .foregroundStyle(theme.muted)
        }
        .padding(.top, 8).padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(leading ? theme.accent : theme.line)
                .frame(height: 2)
        }
        // The whole strip drags, not just the words, so a short lane name is
        // no harder to grab than a long one.
        .contentShape(Rectangle())
        .draggable(DragPayload.lane(lane.id).text)
        .contextMenu {
            Button("Rename…") {
                commitTaskEdit()
                laneEdit = LaneEdit(lane: lane, text: lane.rawValue)
                laneFieldFocused = true
            }
            // Keyboard- and trackpad-free way to do what the drag does; also
            // the only way to reorder when a column is scrolled off-screen.
            Button("Move Left") { store.moveLane(lane, to: index - 1) }
                .disabled(index == 0)
            Button("Move Right") { store.moveLane(lane, to: index + 1) }
                .disabled(index == store.lanes.count - 1)
            Divider()
            // The tasks of a deleted lane fall into the first one left, so
            // the last remaining lane has to stay.
            Button("Delete Lane", role: .destructive) { pendingLaneDeletion = lane }
                .disabled(store.lanes.count == 1)
        }
    }

    /// An empty column holding nothing but the field naming it — the placeholder
    /// a new lane occupies while it is being typed.
    private var newLaneColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            laneNameField(placeholder: "Lane name")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 150, alignment: .top)
    }

    /// The field that names a lane, used for both creating and renaming so the
    /// two read the same.
    private func laneNameField(placeholder: String) -> some View {
        TextField(placeholder, text: Binding(
            get: { laneEdit?.text ?? "" },
            set: { laneEdit?.text = $0 }
        ))
        .textFieldStyle(.plain)
        .font(Typo.sans(12.5))
        .foregroundStyle(theme.text)
        .focused($laneFieldFocused)
        // Focus is taken here rather than where the edit starts: the field
        // doesn't exist yet at that point, so a `@FocusState` set from the
        // menu would land on nothing.
        .onAppear { laneFieldFocused = true }
        .onSubmit { commitLaneEdit() }
        // Escape abandons the name. Without this it falls through to the
        // window, which reads Escape as "close" — a heavy answer to a typo.
        .onExitCommand { cancelLaneEdit() }
        // Clicking away is a cancel, not a commit: a half-typed name
        // shouldn't become a column because focus moved.
        .onChange(of: laneFieldFocused) { _, focused in
            if !focused { laneEdit = nil }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: 1)
        )
    }

    private func cancelLaneEdit() {
        laneEdit = nil
        laneFieldFocused = false
    }

    private func commitLaneEdit() {
        guard let edit = laneEdit else { return }
        if let existing = edit.lane {
            store.renameLane(existing, to: edit.text)
            // Follow the rename, so the add row doesn't silently switch lanes.
            if state.draftLane == existing { state.draftLane = Lane(edit.text) }
        } else if let created = store.addLane(named: edit.text) {
            state.draftLane = created
        }
        laneEdit = nil
        laneFieldFocused = false
    }

    // MARK: - Task rows

    @ViewBuilder
    private func taskRow(_ task: TaskItem, in lane: Lane) -> some View {
        if taskEdit?.id == task.id {
            taskEditor(task)
        } else {
            readOnlyRow(task, in: lane)
        }
    }

    private func readOnlyRow(_ task: TaskItem, in lane: Lane) -> some View {
        let checked = task.done || striking.contains(task.id)
        return HStack(alignment: .top, spacing: 11) {
            checkbox(checked: checked) { toggle(task) }

            VStack(alignment: .leading, spacing: 3) {
                StrikeText(
                    text: task.label,
                    struck: checked,
                    font: Typo.sans(13.5),
                    color: task.done ? theme.muted : theme.text,
                    strikeColor: theme.ok
                )
                .lineSpacing(6)

                if !task.meta.isEmpty {
                    Text(task.meta)
                        .font(Typo.sans(11))
                        .foregroundStyle(theme.muted)
                }
            }

            Spacer(minLength: 8)

            Button {
                commitTaskEdit()
                store.deleteTask(id: task.id)
            } label: {
                Text("×").font(.system(size: 14)).foregroundStyle(theme.muted)
            }
            .buttonStyle(.flat)
            .help("Delete task")
        }
        .padding(.vertical, 12).padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.lineSoft).frame(height: 1)
        }
        .contentShape(Rectangle())
        // Double-click is the fast path; the menu is the discoverable one.
        .onTapGesture(count: 2) { beginEdit(task) }
        .contextMenu {
            Button("Edit…") { beginEdit(task) }
            Divider()
            Menu("Move to") {
                ForEach(store.lanes) { destination in
                    Button(destination.label) { store.move(taskId: task.id, to: destination) }
                        .disabled(destination == lane)
                }
            }
            Divider()
            Button("Delete Task", role: .destructive) { store.deleteTask(id: task.id) }
        }
        .draggable(DragPayload.task(task.id).text)
    }

    /// The row, opened up: label and meta as fields, in place, so the task
    /// stays where it is on the board while you retype it.
    private func taskEditor(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Task", text: Binding(
                get: { taskEdit?.label ?? "" },
                set: { taskEdit?.label = $0 }
            ))
            .font(Typo.sans(13.5))
            .focused($taskField, equals: .label)
            .onExitCommand(perform: cancelTaskEdit)

            TextField("Note", text: Binding(
                get: { taskEdit?.meta ?? "" },
                set: { taskEdit?.meta = $0 }
            ))
            .font(Typo.sans(11))
            .focused($taskField, equals: .meta)
            .onExitCommand(perform: cancelTaskEdit)
        }
        .textFieldStyle(.plain)
        .foregroundStyle(theme.text)
        .onSubmit { commitTaskEdit() }
        // Blur keeps the typing — unlike naming a lane, this is an edit to
        // something that already exists, and losing it to a stray click would
        // cost more than an unwanted rename. Escape still backs out, and
        // clears `taskEdit` first so this commits nothing.
        //
        // This catches focus genuinely moving (Tab, or clicking the search
        // box). The clicks AppKit doesn't turn into a blur at all are caught
        // by the board's tap catcher and by the actions below.
        .onChange(of: taskField) { _, focused in
            if focused == nil { commitTaskEdit() }
        }
        .padding(.vertical, 9).padding(.horizontal, 8)
        .background(theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: 1)
        )
        .padding(.vertical, 3)
        .onAppear { taskField = .label }
        .id(task.id)
    }

    /// Opens a row, saving whichever row was open before it — moving straight
    /// from one task to another is a blur on the first.
    private func beginEdit(_ task: TaskItem) {
        if taskEdit?.id != task.id { commitTaskEdit() }
        taskEdit = TaskEdit(id: task.id, label: task.label, meta: task.meta)
        taskField = .label
    }

    /// Drops the edit without writing it. Clears `taskEdit` before focus goes,
    /// so the commit-on-blur below finds nothing to commit.
    private func cancelTaskEdit() {
        taskEdit = nil
        taskField = nil
    }

    private func commitTaskEdit() {
        guard let edit = taskEdit else { return }
        store.edit(taskId: edit.id, label: edit.label, meta: edit.meta)
        taskEdit = nil
        taskField = nil
    }

    private func checkbox(checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        .padding(.top, 1)
    }

    /// `toggleTask` (:802): un-checking is immediate, checking waits for the
    /// strike to play before the row moves to "Completed today".
    private func toggle(_ task: TaskItem) {
        // Clicking a control on another row is a blur that AppKit doesn't
        // report as one, since a button never takes first responder.
        commitTaskEdit()
        if task.done {
            store.setDone(taskId: task.id, done: false, autoLog: false)
            return
        }
        striking.insert(task.id)
        Task {
            try? await Task.sleep(for: .milliseconds(520))
            striking.remove(task.id)
            store.setDone(taskId: task.id, done: true, autoLog: state.autoLog)
        }
    }

    // MARK: - Completed today

    @ViewBuilder
    private var completedToday: some View {
        let todays = done.filter {
            guard let at = $0.completedAt else { return false }
            return Calendar.current.isDateInToday(at)
        }

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("COMPLETED TODAY")
                    .font(Typo.sans(11, .semibold))
                    .kerning(1.32)
                    .foregroundStyle(theme.ok)
                Text("\(todays.count)")
                    .font(Typo.mono(11.5))
                    .foregroundStyle(theme.muted)
            }

            if !todays.isEmpty {
                FlowLayout(spacing: 18, lineSpacing: 10) {
                    ForEach(todays) { task in
                        Button { toggle(task) } label: {
                            HStack(spacing: 8) {
                                Text(task.label)
                                    .font(Typo.sans(12.5))
                                    .foregroundStyle(theme.muted)
                                    .strikethrough(true, color: theme.ok)
                                if let at = task.completedAt {
                                    Text(Clock.hhmm(at))
                                        .font(Typo.mono(10.5))
                                        .foregroundStyle(theme.muted)
                                }
                            }
                        }
                        .buttonStyle(.flat)
                        .help("Un-complete")
                    }
                }
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
        .padding(.top, 34)
    }
}

/// Which of an open row's two fields has the caret.
private enum TaskField: Hashable { case label, meta }

/// A lane being named: `lane` is nil while creating one, or the lane being
/// renamed. Mirrors `FolderEdit` in Notes.
private struct LaneEdit {
    var lane: Lane?
    var text: String
}

/// A task row opened for editing. Holds its own copies of the two fields so an
/// abandoned edit leaves the stored task untouched.
private struct TaskEdit {
    let id: UUID
    var label: String
    var meta: String
}

/// What a drag on the board is carrying.
///
/// Task rows and lane headers both drag as a plain `String` — one type for one
/// drop destination — so the payload has to say which it is. A bare UUID and a
/// bare lane name are indistinguishable once they're both text.
private enum DragPayload {
    case task(UUID)
    case lane(String)

    private static let taskPrefix = "foglio.task:"
    private static let lanePrefix = "foglio.lane:"

    var text: String {
        switch self {
        case .task(let id): Self.taskPrefix + id.uuidString
        case .lane(let id): Self.lanePrefix + id
        }
    }

    /// Parses by prefix rather than by splitting on the separator: a lane is
    /// named by the user and "Blocked: waiting on infra" is a fair name.
    init?(_ text: String) {
        if text.hasPrefix(Self.taskPrefix),
           let id = UUID(uuidString: String(text.dropFirst(Self.taskPrefix.count))) {
            self = .task(id)
        } else if text.hasPrefix(Self.lanePrefix) {
            self = .lane(String(text.dropFirst(Self.lanePrefix.count)))
        } else {
            return nil
        }
    }
}

/// Wraps a lane in a drop target and hands back whether a drag is over it.
private struct LaneDropTarget<Content: View>: View {
    let theme: Theme
    @ViewBuilder var content: (Bool) -> Content
    let onDrop: (DragPayload) -> Bool

    @State private var targeted = false

    var body: some View {
        content(targeted)
            .dropDestination(for: String.self) { items, _ in
                guard let first = items.first, let payload = DragPayload(first) else { return false }
                return onDrop(payload)
            } isTargeted: { targeted = $0 }
    }
}
