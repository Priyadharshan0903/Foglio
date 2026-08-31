import SwiftUI

/// Three lanes with drag between them, plus today's completions
/// (Day Log.dc.html:312-375).
struct TasksView: View {
    @Bindable var state: AppState
    let store: Store

    /// Tasks mid-strike: checked, but not yet committed as done. The design
    /// holds this for 520ms so the strike animation can play out before the
    /// row disappears into "Completed today" (:806).
    @State private var striking: Set<UUID> = []

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
        }
        .background(theme.bg)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Tasks")
                .font(Typo.sans(19, .semibold))
                .kerning(-0.3)
                .foregroundStyle(theme.text)
            Text("drag a row between lanes")
                .font(Typo.sans(12))
                .foregroundStyle(theme.muted)
            Spacer()
            HStack(spacing: 12) {
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

    private var donePercent: CGFloat {
        guard !store.tasks.isEmpty else { return 0 }
        return CGFloat(done.count) / CGFloat(store.tasks.count)
    }

    // MARK: - Add row

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("Add to \(state.draftLane.label)…", text: $state.draft)
                .textFieldStyle(.plain)
                .font(Typo.sans(13.5))
                .foregroundStyle(theme.text)
                .onSubmit(addDraft)

            HStack(spacing: 3) {
                ForEach(Lane.allCases) { lane in
                    let selected = state.draftLane == lane
                    Button { state.draftLane = lane } label: {
                        Text(lane.label.prefix(3).uppercased())
                            .font(Typo.sans(10.5, .medium))
                            .kerning(0.42)
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
        store.addTask(TaskItem(
            label: label,
            lane: state.draftLane,
            meta: state.draftLane == .delegate ? "Follow up" : ""
        ))
        state.draft = ""
    }

    // MARK: - Lanes

    private var lanes: some View {
        HStack(alignment: .top, spacing: 30) {
            ForEach(Lane.allCases) { lane in
                laneColumn(lane)
            }
        }
        .padding(.top, 28)
    }

    private func laneColumn(_ lane: Lane) -> some View {
        let items = open.filter { $0.lane == lane }
        return LaneDropTarget(theme: theme) { isTargeted in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(lane.label.uppercased())
                        .font(Typo.sans(11, .semibold))
                        .kerning(1.32)
                        .foregroundStyle(lane == .priority ? theme.text : theme.muted)
                    Spacer()
                    Text("\(items.count)")
                        .font(Typo.mono(11.5))
                        .foregroundStyle(theme.muted)
                }
                .padding(.top, 8).padding(.bottom, 9)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(lane == .priority ? theme.accent : theme.line)
                        .frame(height: 2)
                }

                if items.isEmpty {
                    Text(lane.emptyText)
                        .font(Typo.sans(12))
                        .foregroundStyle(theme.muted)
                        .padding(.vertical, 14).padding(.horizontal, 2)
                } else {
                    ForEach(items) { task in
                        taskRow(task)
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
        } onDrop: { idString in
            guard let id = UUID(uuidString: idString) else { return false }
            store.move(taskId: id, to: lane)
            return true
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
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

            Button { store.deleteTask(id: task.id) } label: {
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
        .draggable(task.id.uuidString)
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

/// Wraps a lane in a drop target and hands back whether a drag is over it.
private struct LaneDropTarget<Content: View>: View {
    let theme: Theme
    @ViewBuilder var content: (Bool) -> Content
    let onDrop: (String) -> Bool

    @State private var targeted = false

    var body: some View {
        content(targeted)
            .dropDestination(for: String.self) { items, _ in
                guard let first = items.first else { return false }
                return onDrop(first)
            } isTargeted: { targeted = $0 }
    }
}
