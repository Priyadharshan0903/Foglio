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
    @State private var draggedTaskID: UUID?
    @State private var managingStatuses = false
    @State private var selectedProject: String?
    @State private var selectedPriority: TaskPriority?
    @State private var sort: TaskSort = .manual
    private var projects: [String] { Array(Set(store.tasks.compactMap(\.project).filter { !$0.isEmpty })).sorted() }
    private var theme: Theme { state.theme }
    private var scopedTasks: [TaskItem] {
        store.manuallyOrderedTasks.filter { (selectedProject == nil || $0.project == selectedProject) && (selectedPriority == nil || $0.taskPriority == selectedPriority) }
    }
    private var visible: [TaskItem] {
        sort.ordered(TaskListQuery.filtered(scopedTasks, status: status, list: selectedList, search: state.search, preservingOrder: sort == .manual))
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
        .sheet(isPresented: $managingStatuses) { TaskStatusManager(store: store, theme: theme) }
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
            Button { create(in: store.statuses.first { $0.id == "todo" }!) } label: {
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
                             counts: TaskListQuery.counts(scopedTasks, list: selectedList, search: state.search), theme: theme)
            Spacer(minLength: 0)
            Menu {
                Button("All projects") { selectedProject = nil }
                ForEach(projects, id: \.self) { project in Button(project) { selectedProject = project } }
            } label: { Text(selectedProject ?? "Project").font(Typo.sans(12)).foregroundStyle(theme.muted).lineLimit(1).frame(maxWidth: 140) }
                .menuStyle(.borderlessButton).fixedSize()
            Menu {
                Button("Any priority") { selectedPriority = nil }
                ForEach(TaskPriority.allCases) { priority in Button(priority.label) { selectedPriority = priority } }
            } label: { Text(selectedPriority?.label ?? "Priority").font(Typo.sans(12)).foregroundStyle(theme.muted) }
                .menuStyle(.borderlessButton).fixedSize()
            Menu {
                ForEach(TaskSort.allCases) { order in Button(order.label) { sort = order } }
            } label: { Image(systemName: "arrow.up.arrow.down").foregroundStyle(theme.muted) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Sort: " + sort.label)
                .accessibilityLabel("Sort tasks").accessibilityValue(sort.label)
            Menu {
                Button("All lists") { selectedList = nil }
                Divider()
                ForEach(store.lanes) { lane in Button(lane.label) { selectedList = lane } }
            } label: {
                Label(selectedList?.label ?? "All lists", systemImage: "line.3.horizontal.decrease")
                    .font(Typo.sans(12)).foregroundStyle(theme.muted)
            }.menuStyle(.borderlessButton).fixedSize()
            Menu {
                Button("Manage statuses…") { managingStatuses = true }
                Divider()
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
            let count = CGFloat(store.statuses.count)
            let width = max(300, (geometry.size.width - 48 - 16 * (count - 1)) / count)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(store.statuses) { workflow in
                        column(workflow, width: width, height: geometry.size.height - 32)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 16)
            }
        }
    }

    private func column(_ workflow: TaskBoardStatus, width: CGFloat, height: CGFloat) -> some View {
        let tasks = visible.filter { store.status(for: $0).id == workflow.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                statusIcon(workflow)
                Text(workflow.label).font(Typo.sans(12.5, .semibold)).foregroundStyle(theme.text).lineLimit(1).help(workflow.name)
                Text("\(tasks.count)").font(Typo.sans(11)).foregroundStyle(theme.muted)
                Spacer(minLength: 0)
                Menu {
                    Button("Manage statuses…") { managingStatuses = true }
                } label: { Image(systemName: "ellipsis").foregroundStyle(theme.muted) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Rename or reorder statuses")
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
            .anchorPreference(key: TaskColumnViewportKey.self, value: .bounds) { $0 }
        }
        .padding(8).frame(width: width, height: max(180, height), alignment: .topLeading)
        .modifier(TaskColumnDropTarget(taskIDs: tasks.map(\.id), draggedID: draggedTaskID, theme: theme) { id, placement in
            if store.placeTask(taskId: id, statusID: workflow.id, relativeTo: placement?.anchorID,
                               after: placement?.after ?? false, autoLog: state.autoLog) { sort = .manual }
        })
    }

    private func card(_ task: TaskItem) -> some View {
        Button { taskEdit = TaskPresentation(task: task, isNew: false) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(task.ticketID).font(Typo.mono(10.5)).foregroundStyle(theme.muted)
                    Spacer()
                    if task.taskPriority != .none {
                        Label(task.taskPriority.label, systemImage: task.taskPriority.symbol)
                            .font(Typo.sans(10.5)).foregroundStyle(theme.accentDeep)
                    }
                }
                Text(task.label).font(Typo.sans(13, .medium)).foregroundStyle(task.done ? theme.muted : theme.text)
                    .lineLimit(3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if !task.summary.isEmpty {
                    Text(task.summary).font(Typo.sans(11.5)).foregroundStyle(theme.muted)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                if let project = task.project, !project.isEmpty {
                    Label(project, systemImage: "square.stack").font(Typo.sans(10.5))
                        .foregroundStyle(theme.muted).lineLimit(1)
                }
                HStack(spacing: 6) {
                    statusIcon(store.status(for: task))
                    Text(task.lane.label).font(Typo.sans(10.5)).foregroundStyle(theme.muted)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(theme.field).clipShape(RoundedRectangle(cornerRadius: 4))
                    Spacer(minLength: 0)
                    if let date = task.dueDate {
                        Label(date.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                            .font(Typo.sans(10.5)).foregroundStyle(!task.done && date < Calendar.current.startOfDay(for: Clock.now()) ? theme.clay : theme.muted)
                    }
                    if let estimate = task.estimate { Text("\(estimate) pts").font(Typo.sans(10.5)).foregroundStyle(theme.muted) }
                }
                let children = store.tasks.filter { $0.parentID == task.id }
                let blockers = store.tasks.filter { (task.blockedBy ?? []).contains($0.id) && !$0.done }
                if !children.isEmpty || !blockers.isEmpty {
                    HStack(spacing: 12) {
                        if !blockers.isEmpty {
                            Label("Blocked · \(blockers.count)", systemImage: "link").foregroundStyle(theme.clay)
                        }
                        if !children.isEmpty {
                            Label("\(children.filter(\.done).count)/\(children.count)", systemImage: "checklist").foregroundStyle(theme.muted)
                        }
                    }.font(Typo.sans(10.5))
                }
                if !(task.labels ?? []).isEmpty || task.assignee != nil {
                    HStack(spacing: 6) {
                        ForEach(Array((task.labels ?? []).prefix(2)), id: \.self) { label in
                            Text(label).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 3)
                                .background(theme.accentSoft).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        if (task.labels ?? []).count > 2 { Text("+\((task.labels ?? []).count - 2)") }
                        Spacer(minLength: 0)
                        if let assignee = task.assignee { Text(assignee).lineLimit(1) }
                    }.font(Typo.sans(10)).foregroundStyle(theme.muted)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line, lineWidth: 1)).hoverHighlight(theme)
        }.buttonStyle(.flat)
            .overlay {
                TaskCardDragSource(taskID: task.id, onOpen: { taskEdit = TaskPresentation(task: task, isNew: false) },
                                   onDragChanged: { draggedTaskID = $0 })
                    .accessibilityHidden(true)
            }
            .contextMenu { taskActions(task) }.help("Open \(task.label)")
            .anchorPreference(key: TaskCardBoundsKey.self, value: .bounds) { [task.id: $0] }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.statuses) { workflow in
                    let tasks = visible.filter { store.status(for: $0).id == workflow.id }
                    if !tasks.isEmpty {
                        HStack(spacing: 8) {
                            statusIcon(workflow)
                            Text(workflow.label).font(Typo.sans(12, .semibold)).foregroundStyle(theme.text)
                            Text("\(tasks.count)").font(Typo.sans(11)).foregroundStyle(theme.muted)
                        }.padding(.horizontal, 24).padding(.vertical, 12).background(theme.field)
                        ForEach(tasks) { task in
                            Button { taskEdit = TaskPresentation(task: task, isNew: false) } label: {
                                HStack(spacing: 12) {
                                    statusIcon(store.status(for: task))
                                    Text(task.ticketID).font(Typo.mono(11)).foregroundStyle(theme.muted).frame(width: 72, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.label).font(Typo.sans(13)).foregroundStyle(task.done ? theme.muted : theme.text).lineLimit(2)
                                        if let project = task.project { Text(project).font(Typo.sans(11)).foregroundStyle(theme.muted) }
                                    }
                                    if task.taskPriority != .none { Text(task.taskPriority.label).font(Typo.sans(11)).foregroundStyle(theme.accentDeep) }
                                    if let date = task.dueDate { Text(date, format: .dateTime.month(.abbreviated).day()).font(Typo.sans(11)).foregroundStyle(theme.muted) }
                                    Spacer(minLength: 12)
                                    Text(task.lane.label).font(Typo.sans(11)).foregroundStyle(theme.muted)
                                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(theme.muted)
                                }
                                .padding(.horizontal, 24).padding(.vertical, 13).hoverHighlight(theme, cornerRadius: 0)
                                .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
                            }.buttonStyle(.flat)
                                .overlay {
                                    TaskCardDragSource(taskID: task.id, onOpen: { taskEdit = TaskPresentation(task: task, isNew: false) },
                                                       onDragChanged: { draggedTaskID = $0 })
                                        .accessibilityHidden(true)
                                }
                                .contextMenu { taskActions(task) }
                                .modifier(TaskInsertionTarget(taskID: task.id, draggedID: draggedTaskID, theme: theme) { id, after in
                                    place(id, beside: task, after: after)
                                })
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
        let peers = visible.filter { store.status(for: $0).id == store.status(for: task).id }
        if let index = peers.firstIndex(where: { $0.id == task.id }) {
            Button("Move up") { place(task.id, beside: peers[index - 1], after: false) }.disabled(index == 0)
            Button("Move down") { place(task.id, beside: peers[index + 1], after: true) }.disabled(index == peers.count - 1)
        }
        Menu("Set status") {
            ForEach(store.statuses) { workflow in
                Button(workflow.label) { store.setStatus(taskId: task.id, statusID: workflow.id, autoLog: state.autoLog) }
                    .disabled(store.status(for: task).id == workflow.id)
            }
        }
        Menu("Set priority") {
            ForEach(TaskPriority.allCases) { priority in
                Button(priority.label) { var updated = task; updated.priority = priority; store.update(updated) }
            }
        }
        Button("Copy ticket ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(task.ticketID, forType: .string) }
        Menu("Move to list") {
            ForEach(store.lanes) { lane in Button(lane.label) { store.move(taskId: task.id, to: lane) }.disabled(task.lane == lane) }
        }
        Divider()
        Button("Delete task", role: .destructive) { delete(task) }
    }

    private func statusIcon(_ workflow: TaskBoardStatus) -> some View {
        Image(systemName: workflow.symbol).font(.system(size: 12))
            .foregroundStyle([.inProgress, .done].contains(workflow.category) ? theme.accentDeep : theme.muted)
    }
    private func place(_ id: UUID, beside task: TaskItem, after: Bool) {
        if store.placeTask(taskId: id, statusID: store.status(for: task).id, relativeTo: task.id,
                           after: after, autoLog: state.autoLog) { sort = .manual }
    }
    private func create(in workflow: TaskBoardStatus) {
        taskEdit = TaskPresentation(task: TaskItem(lane: selectedList ?? store.defaultLane,
                                                  done: workflow.category == .done, workflow: workflow.category, statusID: workflow.id), isNew: true)
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
