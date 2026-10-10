import SwiftUI
import AppKit

/// Room for the document and its properties without putting metadata in prose.
struct TaskDetailEditor: View {
    let task: TaskItem
    let isNew: Bool
    let store: Store
    let theme: Theme
    let autoLog: Bool
    let onClose: () -> Void
    let onDelete: () -> Void
    @Binding var closeOnOutsideClick: Bool
    @State private var name: String
    @State private var details: String
    @State private var statusID: String
    @State private var lane: Lane
    @State private var priority: TaskPriority
    @State private var project: String
    @State private var assignee: String
    @State private var labels: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var parentID: UUID?
    @State private var blockedBy: Set<UUID>
    @State private var estimate: Int
    @State private var saveError: String?
    @State private var controller = NoteEditorController()
    @State private var confirmingClose = false
    @FocusState private var nameFocused: Bool
    @FocusState private var cardFocused: Bool

    init(task: TaskItem, isNew: Bool, store: Store, theme: Theme, autoLog: Bool,
         closeOnOutsideClick: Binding<Bool> = .constant(true),
         onClose: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.task = task; self.isNew = isNew; self.store = store; self.theme = theme
        self.autoLog = autoLog; self.onClose = onClose; self.onDelete = onDelete
        _closeOnOutsideClick = closeOnOutsideClick
        _name = State(initialValue: task.label); _details = State(initialValue: task.meta)
        _statusID = State(initialValue: store.status(for: task).id); _lane = State(initialValue: task.lane)
        _priority = State(initialValue: task.taskPriority)
        _project = State(initialValue: task.project ?? ""); _assignee = State(initialValue: task.assignee ?? "")
        _labels = State(initialValue: (task.labels ?? []).joined(separator: ", "))
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? Calendar.current.startOfDay(for: Clock.now()))
        _estimate = State(initialValue: task.estimate ?? 0)
        _parentID = State(initialValue: task.parentID)
        _blockedBy = State(initialValue: Set(task.blockedBy ?? []))
    }
    private var labelValues: [String] {
        var seen = Set<String>()
        return labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 400
            && project.count <= 120 && assignee.count <= 120 && labelValues.count <= 20
            && labelValues.allSatisfy { $0.utf8.count <= 80 }
    }
    private var hasChanges: Bool {
        name != task.label || details != task.meta || statusID != store.status(for: task).id || lane != task.lane
            || priority != task.taskPriority || project != (task.project ?? "") || assignee != (task.assignee ?? "")
            || labelValues != (task.labels ?? []) || hasDueDate != (task.dueDate != nil)
            || (hasDueDate && dueDate != task.dueDate) || estimate != (task.estimate ?? 0) || parentID != task.parentID || blockedBy != Set(task.blockedBy ?? [])
    }
    private var size: CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 1000)
        return CGSize(width: min(1080, max(740, screen.width - 100)), height: min(800, max(540, screen.height - 100)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Task title", text: $name, axis: .vertical)
                        .textFieldStyle(.plain).font(Typo.sans(25, .semibold)).foregroundStyle(theme.text)
                        .lineLimit(1...4).focused($nameFocused).padding(26)
                    RichTextEditor(id: task.id, markdown: $details, controller: controller, theme: theme, baseURL: store.root,
                                   placeholder: "Add a description…", accessibilityName: "Task description")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                properties.frame(width: 240).frame(maxHeight: .infinity, alignment: .top)
                    .background(theme.field.opacity(0.45))
                    .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 1) }
            }
            footer
        }
        .frame(width: size.width, height: size.height).background(theme.surface).tint(theme.accentDeep)
        .focusable().focused($cardFocused).focusEffectDisabled().defaultFocus($cardFocused, !isNew)
        .background {
            TaskOutsideClickMonitor(enabled: closeOnOutsideClick && !confirmingClose, onOutside: requestClose)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .interactiveDismissDisabled()
        .onAppear { if !isNew { store.editingTaskIds.insert(task.id) } }
        .onDisappear { store.editingTaskIds.remove(task.id) }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onExitCommand(perform: requestClose).task {
            if isNew { nameFocused = true } else { cardFocused = true }
        }
        .alert(isNew ? "Save this new task?" : "Save changes to this task?", isPresented: $confirmingClose) {
            Button(isNew ? "Create task" : "Save changes", action: save).disabled(!valid)
            Button("Discard changes", role: .destructive, action: onClose)
            Button("Keep editing", role: .cancel) {}
        } message: { Text("You have unsaved changes. Save them or keep editing.") }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack").foregroundStyle(theme.muted)
            Text(lane.label).font(Typo.sans(12)).foregroundStyle(theme.muted)
            Text("/").foregroundStyle(theme.muted)
            if isNew { Text("New task").font(Typo.sans(12)).foregroundStyle(theme.muted) }
            else {
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(task.ticketID, forType: .string)
                } label: {
                    Label(task.ticketID, systemImage: "doc.on.doc").font(Typo.mono(12)).foregroundStyle(theme.accentDeep)
                }.buttonStyle(.flat).help("Copy ticket ID")
            }
            Spacer()
            Menu { Toggle("Close when clicking outside", isOn: $closeOnOutsideClick) } label: {
                Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(theme.muted).frame(width: 28, height: 28)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Task editor options")
            Button(action: requestClose) {
                Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(theme.muted)
                    .frame(width: 28, height: 28).hoverHighlight(theme, cornerRadius: 5)
            }.buttonStyle(.flat).help("Close").accessibilityLabel("Close task editor")
        }.padding(.horizontal, 24).padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }
    private var properties: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Properties").font(Typo.sans(12, .semibold)).foregroundStyle(theme.text)
                property("Status") {
                    Menu {
                        ForEach(store.statuses) { status in Button(status.name) { statusID = status.id } }
                    } label: {
                        let status = store.statuses.first { $0.id == statusID } ?? store.status(for: task)
                        Label(status.name, systemImage: status.symbol)
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                property("Priority") {
                    Menu {
                        ForEach(TaskPriority.allCases) { value in Button(value.label) { priority = value } }
                    } label: { Label(priority.label, systemImage: priority.symbol) }
                        .menuStyle(.borderlessButton).fixedSize()
                }
                property("List") {
                    Menu { ForEach(store.lanes) { list in Button(list.label) { lane = list } } }
                    label: { Label(lane.label, systemImage: "list.bullet") }
                        .menuStyle(.borderlessButton).fixedSize()
                }
                property("Project") { propertyField("Add project", text: $project) }
                property("Assignee") { propertyField("Unassigned", text: $assignee) }
                property("Labels") {
                    propertyField("Add labels, separated by commas", text: $labels)
                    if !labelValues.isEmpty {
                        Text(labelValues.joined(separator: " · ")).font(Typo.sans(11)).foregroundStyle(theme.muted)
                    }
                }
                property("Due date") {
                    Toggle("Set due date", isOn: $hasDueDate).toggleStyle(.checkbox)
                    if hasDueDate {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                    }
                }
                property("Estimate") {
                    Stepper(value: $estimate, in: 0...100) {
                        Text(estimate == 0 ? "No estimate" : "\(estimate) points")
                    }
                }
                property("Parent task") {
                    Menu {
                        Button("No parent") { parentID = nil }
                        ForEach(store.tasks.filter { $0.id != task.id }) { item in
                            Button(item.ticketID + " · " + item.label) { parentID = item.id }
                        }
                    } label: {
                        Text(store.tasks.first { $0.id == parentID }.map { $0.ticketID + " · " + $0.label } ?? "No parent")
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }.menuStyle(.borderlessButton)
                }
                property("Blocked by") {
                    Menu {
                        Button("Clear blockers") { blockedBy.removeAll() }
                        ForEach(store.tasks.filter { $0.id != task.id }) { item in
                            Toggle(item.ticketID + " · " + item.label, isOn: Binding(
                                get: { blockedBy.contains(item.id) },
                                set: { if $0 { blockedBy.insert(item.id) } else { blockedBy.remove(item.id) } }))
                        }
                    } label: { Text(blockedBy.isEmpty ? "No dependencies" : "\(blockedBy.count) dependencies") }
                        .menuStyle(.borderlessButton)
                    ForEach(store.tasks.filter { blockedBy.contains($0.id) }) { item in
                        Label(item.ticketID + " · " + item.label, systemImage: item.done ? "checkmark.circle" : "circle")
                            .font(Typo.sans(11)).foregroundStyle(theme.muted).lineLimit(2)
                    }
                }
                let children = store.tasks.filter { $0.parentID == task.id }
                if !children.isEmpty {
                    property("Subtasks · \(children.filter(\.done).count)/\(children.count)") {
                        ForEach(children) { item in
                            Label(item.ticketID + " · " + item.label, systemImage: item.done ? "checkmark.circle" : "circle")
                                .font(Typo.sans(11)).foregroundStyle(theme.muted).lineLimit(2)
                        }
                    }
                }
                if !isNew {
                    Divider().overlay(theme.line)
                    Text("Created " + task.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(Typo.sans(10.5)).foregroundStyle(theme.muted)
                }
            }.padding(20)
        }
    }
    private func property<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typo.sans(10.5, .medium)).foregroundStyle(theme.muted)
            content().font(Typo.sans(12)).foregroundStyle(theme.accentDeep)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func propertyField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain).foregroundStyle(theme.text)
            .padding(8).background(theme.field).clipShape(RoundedRectangle(cornerRadius: 5))
    }
    private var footer: some View {
        HStack(spacing: 12) {
            if !isNew {
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(theme.clay).frame(width: 28, height: 28).hoverHighlight(theme)
                }.buttonStyle(.flat).help("Delete task").accessibilityLabel("Delete task")
            }
            if let saveError { Text(saveError).font(Typo.sans(11)).foregroundStyle(theme.clay).lineLimit(2) }
            else if !valid { Text("Add a title and keep property values within their limits.").font(Typo.sans(11)).foregroundStyle(theme.muted) }
            Spacer()
            Button("Cancel", action: requestClose).buttonStyle(.flat).font(Typo.sans(12)).foregroundStyle(theme.muted)
                .padding(.horizontal, 10).frame(height: 32).hoverHighlight(theme)
            Button(isNew ? "Create task" : "Save changes", action: save)
                .buttonStyle(.flat).font(Typo.sans(12, .semibold)).foregroundStyle(valid ? theme.onAccent : theme.muted)
                .padding(.horizontal, 14).frame(height: 32).background(valid ? theme.accent : theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 7)).disabled(!valid)
                .keyboardShortcut(.return, modifiers: [.command, .shift]).help("Save (⌘⇧Return)")
        }.padding(16).overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }
    private func requestClose() {
        if hasChanges { confirmingClose = true } else { onClose() }
    }
    private func save() {
        guard valid else { nameFocused = true; return }
        var updated = store.tasks.first { $0.id == task.id } ?? task
        updated.label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.meta = details.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.lane = store.lanes.contains(lane) ? lane : store.defaultLane
        updated.priority = priority
        updated.project = project.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.assignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.labels = labelValues; updated.dueDate = hasDueDate ? dueDate : nil
        updated.estimate = estimate == 0 ? nil : estimate
        updated.parentID = parentID
        updated.blockedBy = blockedBy.sorted { $0.uuidString < $1.uuidString }
        do { try TaskRelations.validate(updated, among: store.tasks) }
        catch { saveError = error.localizedDescription; return }
        if isNew && !store.tasks.contains(where: { $0.id == task.id }) { updated.done = false; updated.completedAt = nil }
        store.clearPersistenceError()
        if isNew && !store.tasks.contains(where: { $0.id == task.id }) { store.addTask(updated) }
        else { store.update(updated) }
        store.setStatus(taskId: task.id, statusID: statusID, autoLog: autoLog)
        if let error = store.persistenceError { saveError = "Could not save: " + error; return }
        onClose()
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
