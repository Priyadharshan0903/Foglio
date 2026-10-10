import SwiftUI

/// Only an outside click dismisses the card; editor focus changes keep the
/// draft intact, and closing a changed draft asks before discarding it.
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
    @State private var workflow: TaskWorkflow
    @State private var lane: Lane
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
        _workflow = State(initialValue: task.workflowStatus); _lane = State(initialValue: task.lane)
    }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasChanges: Bool {
        name != task.label || details != task.meta || workflow != task.workflowStatus || lane != task.lane
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? "New task" : "Task details").font(Typo.sans(11.5, .medium)).foregroundStyle(theme.muted)
                Spacer()
                Menu {
                    Toggle("Close when clicking outside", isOn: $closeOnOutsideClick)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(theme.muted)
                        .frame(width: 28, height: 28)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Task editor options").accessibilityLabel("Task editor options")
                Button(action: requestClose) {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(theme.muted)
                        .frame(width: 28, height: 28).hoverHighlight(theme, cornerRadius: 5)
                }.buttonStyle(.flat).help("Close").accessibilityLabel("Close task editor")
            }.padding(.horizontal, 24).padding(.top, 16)
            TextField("Task title", text: $name, axis: .vertical)
                .textFieldStyle(.plain).font(Typo.sans(22, .semibold)).foregroundStyle(theme.text)
                .lineLimit(1...3).focused($nameFocused).padding(.horizontal, 24).padding(.top, 12)
            if !valid && !isNew {
                Text("Give this task a title before saving.").font(Typo.sans(11)).foregroundStyle(theme.clay)
                    .padding(.horizontal, 24).padding(.top, 6)
            }
            HStack(spacing: 16) {
                Menu {
                    ForEach(TaskWorkflow.allCases) { status in Button(status.label) { workflow = status } }
                } label: {
                    Label(workflow.label, systemImage: workflow.symbol).font(Typo.sans(12)).foregroundStyle(theme.accentDeep)
                }.menuStyle(.borderlessButton).fixedSize()
                Menu {
                    ForEach(store.lanes) { list in Button(list.label) { lane = list } }
                } label: {
                    Label(lane.label, systemImage: "list.bullet").font(Typo.sans(12)).foregroundStyle(theme.muted)
                }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
            }.padding(.horizontal, 24).padding(.vertical, 18)
            RichTextEditor(id: task.id, markdown: $details, controller: controller, theme: theme, baseURL: store.root,
                           placeholder: "Add a description…", accessibilityName: "Task description")
            HStack(spacing: 12) {
                if !isNew {
                    Button(action: onDelete) {
                        Image(systemName: "trash").foregroundStyle(theme.clay).frame(width: 28, height: 28).hoverHighlight(theme)
                    }.buttonStyle(.flat).help("Delete task").accessibilityLabel("Delete task")
                }
                Spacer()
                Button("Cancel", action: requestClose).buttonStyle(.flat).font(Typo.sans(12)).foregroundStyle(theme.muted)
                    .padding(.horizontal, 10).frame(height: 32).hoverHighlight(theme)
                Button(isNew ? "Create task" : "Save changes", action: save)
                    .buttonStyle(.flat).font(Typo.sans(12, .semibold)).foregroundStyle(valid ? theme.onAccent : theme.muted)
                    .padding(.horizontal, 14).frame(height: 32).background(valid ? theme.accent : theme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 7)).disabled(!valid)
                    .keyboardShortcut(.return, modifiers: [.command, .shift]).help("Save (⌘⇧Return)")
            }
            .padding(16).overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
        }
        .frame(width: 680, height: 620).background(theme.surface).tint(theme.accentDeep)
        .focusable().focused($cardFocused).focusEffectDisabled()
        .defaultFocus($cardFocused, !isNew)
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
        } message: {
            Text(valid ? "You have unsaved changes." : "Add a title to save this task, or discard your changes.")
        }
    }
    private func requestClose() {
        if hasChanges { confirmingClose = true } else { onClose() }
    }
    private func save() {
        guard valid else { nameFocused = true; return }
        if isNew {
            store.addTask(TaskItem(id: task.id, label: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                   lane: lane, meta: details.trimmingCharacters(in: .whitespacesAndNewlines)))
        } else {
            store.edit(taskId: task.id, label: name, meta: details)
            if lane != task.lane { store.move(taskId: task.id, to: lane) }
        }
        store.setWorkflow(taskId: task.id, status: workflow, autoLog: autoLog)
        onClose()
    }
}
