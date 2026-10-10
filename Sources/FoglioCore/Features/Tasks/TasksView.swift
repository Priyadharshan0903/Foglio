import SwiftUI

struct TasksView: View {
    @Bindable var state: AppState
    let store: Store
    @State private var status: TaskStatus = .all
    @State private var selectedList: Lane?
    @State private var taskEdit: TaskPresentation?
    @State private var laneEdit: LaneEdit?
    @FocusState private var laneFieldFocused: Bool
    @State private var pendingLaneDeletion: Lane?
    @State private var deletedTask: TaskItem?
    @State private var dropTarget: TaskWorkflow?
    private var theme: Theme { state.theme }
    private var visible: [TaskItem] {
        TaskListQuery.filtered(store.tasks, status: status, list: selectedList, search: state.search)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            filters
            if laneEdit != nil { listNameField.padding(.horizontal, 24).padding(.bottom, 12) }
            if let deletedTask {
                HStack {
                    Text("Task deleted").foregroundStyle(theme.muted)
                    Spacer()
                    Button("Undo") { store.addTask(deletedTask); self.deletedTask = nil }
                        .buttonStyle(.flat).foregroundStyle(theme.accentDeep)
                }
                .font(Typo.sans(12)).padding(10).background(theme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 7)).padding(.horizontal, 24).padding(.bottom, 12)
            }
            if state.taskLayout == .board { board } else { list }
        }
        .background(theme.bg).tint(theme.accentDeep)
        .onChange(of: store.lanes) { _, lanes in
            if let selectedList, !lanes.contains(selectedList) { self.selectedList = nil }
        }
        .sheet(item: $taskEdit) { presentation in
            TaskDetailEditor(task: presentation.task, isNew: presentation.isNew, store: store,
                             theme: theme, autoLog: state.autoLog,
                             closeOnOutsideClick: $state.closeTaskOnOutsideClick,
                             onClose: { taskEdit = nil },
                             onDelete: { delete(presentation.task); taskEdit = nil })
        }
        .confirmationDialog(pendingLaneDeletion.map { "Delete “\($0.label)”?" } ?? "",
                            isPresented: Binding(get: { pendingLaneDeletion != nil }, set: { if !$0 { pendingLaneDeletion = nil } }),
                            titleVisibility: .visible) {
            Button("Delete List", role: .destructive) {
                if let lane = pendingLaneDeletion { store.deleteLane(lane) }
                pendingLaneDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingLaneDeletion = nil }
        } message: { Text("Its tasks move to the first remaining list.") }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tasks").font(Typo.sans(24, .semibold)).foregroundStyle(theme.text)
                Text("\(store.tasks.filter { !$0.done }.count) open · \(store.tasks.filter(\.done).count) completed")
                    .font(Typo.sans(12)).foregroundStyle(theme.muted)
            }
            Spacer()
            Button { create(in: .todo) } label: {
                Label("New task", systemImage: "plus")
                    .font(Typo.sans(12, .semibold)).foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(theme.accent).clipShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.flat)
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 18)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                layoutButton(.board, symbol: "rectangle.split.3x1", label: "Board")
                layoutButton(.list, symbol: "list.bullet", label: "List")
            }.padding(3).background(theme.field).clipShape(RoundedRectangle(cornerRadius: 7))
            TaskStatusFilter(selection: $status,
                             counts: TaskListQuery.counts(store.tasks, list: selectedList, search: state.search), theme: theme)
            Spacer(minLength: 0)
            Menu {
                Button("All lists") { selectedList = nil }
                Divider()
                ForEach(store.lanes) { lane in Button(lane.label) { selectedList = lane } }
            } label: {
                Label(selectedList?.label ?? "All lists", systemImage: "line.3.horizontal.decrease")
                    .font(Typo.sans(12)).foregroundStyle(theme.muted)
            }.menuStyle(.borderlessButton).fixedSize()
            Menu {
                Button("New list…") { laneEdit = LaneEdit(lane: nil, text: "") }
                if let selectedList {
                    Button("Rename list…") { laneEdit = LaneEdit(lane: selectedList, text: selectedList.rawValue) }
                    Button("Delete list…", role: .destructive) { pendingLaneDeletion = selectedList }.disabled(store.lanes.count == 1)
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(theme.muted).frame(width: 24, height: 24)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Manage lists")
        }
        .padding(.horizontal, 24).padding(.bottom, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    private func layoutButton(_ layout: TaskLayout, symbol: String, label: String) -> some View {
        let active = state.taskLayout == layout
        return Button { state.taskLayout = layout } label: {
            Image(systemName: symbol).font(.system(size: 12))
                .foregroundStyle(active ? theme.accentDeep : theme.muted).frame(width: 30, height: 27)
                .background(active ? theme.accentSoft : .clear).clipShape(RoundedRectangle(cornerRadius: 5))
                .hoverHighlight(theme, cornerRadius: 5, active: !active)
        }.buttonStyle(.flat).help(label).accessibilityLabel(label)
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var board: some View {
        GeometryReader { geometry in
            let width = max(232, (geometry.size.width - 84) / 4)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(TaskWorkflow.allCases) { workflow in
                        column(workflow, width: width, height: geometry.size.height - 32)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 16)
            }
        }
    }

    private func column(_ workflow: TaskWorkflow, width: CGFloat, height: CGFloat) -> some View {
        let tasks = visible.filter { $0.workflowStatus == workflow }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                statusIcon(workflow)
                Text(workflow.label).font(Typo.sans(12.5, .semibold)).foregroundStyle(theme.text)
                Text("\(tasks.count)").font(Typo.sans(11)).foregroundStyle(theme.muted)
                Spacer(minLength: 0)
                Button { create(in: workflow) } label: {
                    Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(theme.muted)
                        .frame(width: 26, height: 26).hoverHighlight(theme, cornerRadius: 5)
                }.buttonStyle(.flat).help("Add task to \(workflow.label)").accessibilityLabel("Add task to \(workflow.label)")
            }.padding(.horizontal, 4)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in card(task) }
                    if tasks.isEmpty {
                        Text(state.search.isEmpty ? "No tasks" : "No matching tasks")
                            .font(Typo.sans(11.5)).foregroundStyle(theme.muted).frame(maxWidth: .infinity, minHeight: 70)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    }
                    Button { create(in: workflow) } label: {
                        Label("Add task", systemImage: "plus").font(Typo.sans(11.5)).foregroundStyle(theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10).hoverHighlight(theme)
                    }.buttonStyle(.flat)
                }.padding(4)
            }
        }
        .padding(8).frame(width: width, height: max(180, height), alignment: .topLeading)
        .background(dropTarget == workflow ? theme.accentSoft : theme.field.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(dropTarget == workflow ? theme.accentDeep : .clear, lineWidth: 1))
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap { value -> UUID? in
                guard value.hasPrefix("foglio-task:") else { return nil }
                return UUID(uuidString: String(value.dropFirst("foglio-task:".count)))
            }.filter { id in store.tasks.contains { $0.id == id } }
            for id in ids { store.setWorkflow(taskId: id, status: workflow, autoLog: state.autoLog) }
            return !ids.isEmpty
        } isTargeted: { targeted in
            if targeted { dropTarget = workflow } else if dropTarget == workflow { dropTarget = nil }
        }
    }

    private func card(_ task: TaskItem) -> some View {
        Button { taskEdit = TaskPresentation(task: task, isNew: false) } label: {
            VStack(alignment: .leading, spacing: 14) {
                Text(task.label).font(Typo.sans(13, .medium)).foregroundStyle(task.done ? theme.muted : theme.text)
                    .lineLimit(4).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    statusIcon(task.workflowStatus)
                    Text(task.lane.label).font(Typo.sans(10.5)).foregroundStyle(theme.muted)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(theme.field).clipShape(RoundedRectangle(cornerRadius: 4))
                    Spacer(minLength: 0)
                    if !task.meta.isEmpty { Image(systemName: "text.alignleft").font(.system(size: 10)).foregroundStyle(theme.muted) }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line, lineWidth: 1)).hoverHighlight(theme)
        }.buttonStyle(.flat)
            .overlay {
                TaskCardDragSource(taskID: task.id) { taskEdit = TaskPresentation(task: task, isNew: false) }
                    .accessibilityHidden(true)
            }
            .contextMenu { taskActions(task) }.help("Open \(task.label)")
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(TaskWorkflow.allCases) { workflow in
                    let tasks = visible.filter { $0.workflowStatus == workflow }
                    if !tasks.isEmpty {
                        HStack(spacing: 8) {
                            statusIcon(workflow)
                            Text(workflow.label).font(Typo.sans(12, .semibold)).foregroundStyle(theme.text)
                            Text("\(tasks.count)").font(Typo.sans(11)).foregroundStyle(theme.muted)
                        }.padding(.horizontal, 24).padding(.vertical, 12).background(theme.field)
                        ForEach(tasks) { task in
                            Button { taskEdit = TaskPresentation(task: task, isNew: false) } label: {
                                HStack(spacing: 12) {
                                    statusIcon(task.workflowStatus)
                                    Text(task.label).font(Typo.sans(13)).foregroundStyle(task.done ? theme.muted : theme.text).lineLimit(1)
                                    Spacer(minLength: 12)
                                    Text(task.lane.label).font(Typo.sans(11)).foregroundStyle(theme.muted)
                                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(theme.muted)
                                }
                                .padding(.horizontal, 24).padding(.vertical, 13).hoverHighlight(theme, cornerRadius: 0)
                                .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
                            }.buttonStyle(.flat).contextMenu { taskActions(task) }
                        }
                    }
                }
                if visible.isEmpty {
                    Text(state.search.isEmpty ? "No tasks in this view. Add a task to get started." : "No matching tasks. Try another search or list.")
                        .font(Typo.sans(13)).foregroundStyle(theme.muted).padding(32)
                }
            }
        }
    }

    @ViewBuilder private func taskActions(_ task: TaskItem) -> some View {
        Button("Open task…") { taskEdit = TaskPresentation(task: task, isNew: false) }
        Menu("Set status") {
            ForEach(TaskWorkflow.allCases) { workflow in
                Button(workflow.label) { store.setWorkflow(taskId: task.id, status: workflow, autoLog: state.autoLog) }
                    .disabled(task.workflowStatus == workflow)
            }
        }
        Menu("Move to list") {
            ForEach(store.lanes) { lane in Button(lane.label) { store.move(taskId: task.id, to: lane) }.disabled(task.lane == lane) }
        }
        Divider()
        Button("Delete task", role: .destructive) { delete(task) }
    }

    private func statusIcon(_ workflow: TaskWorkflow) -> some View {
        Image(systemName: workflow.symbol).font(.system(size: 12))
            .foregroundStyle([.inProgress, .done].contains(workflow) ? theme.accentDeep : theme.muted)
    }
    private func create(in workflow: TaskWorkflow) {
        taskEdit = TaskPresentation(task: TaskItem(lane: selectedList ?? store.defaultLane,
                                                  done: workflow == .done, workflow: workflow), isNew: true)
    }
    private func delete(_ task: TaskItem) {
        deletedTask = store.tasks.first { $0.id == task.id } ?? task
        store.deleteTask(id: task.id)
    }

    private var listNameField: some View {
        HStack(spacing: 12) {
            TextField("List name", text: Binding(get: { laneEdit?.text ?? "" }, set: { laneEdit?.text = $0 }))
                .textFieldStyle(.plain).focused($laneFieldFocused).onSubmit(commitLaneEdit).onExitCommand { laneEdit = nil }
            Button("Cancel") { laneEdit = nil }.buttonStyle(.flat)
            Button("Save", action: commitLaneEdit).buttonStyle(.flat).foregroundStyle(theme.accentDeep)
        }
        .font(Typo.sans(12.5)).foregroundStyle(theme.text).padding(14).background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8)).onAppear { laneFieldFocused = true }
    }
    private func commitLaneEdit() {
        guard let edit = laneEdit, !edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let lane = edit.lane { store.renameLane(lane, to: edit.text); selectedList = Lane(edit.text) }
        else if let lane = store.addLane(named: edit.text) { selectedList = lane }
        laneEdit = nil
    }
}

private struct LaneEdit { var lane: Lane?; var text: String }
private struct TaskPresentation: Identifiable {
    let task: TaskItem
    let isNew: Bool
    var id: UUID { task.id }
}
