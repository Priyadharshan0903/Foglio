import SwiftUI

struct TaskStatusManager: View {
    let store: Store
    let theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: String?
    @State private var name = ""
    @State private var category: TaskWorkflow = .todo
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workflow statuses").font(Typo.sans(22, .semibold))
                    Text("Name the steps your work moves through.").font(Typo.sans(12)).foregroundStyle(theme.muted)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.flat).foregroundStyle(theme.accentDeep)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.statuses.enumerated()), id: \.element.id) { index, status in
                        HStack(spacing: 12) {
                            Image(systemName: status.symbol).foregroundStyle(theme.accentDeep)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(status.name).font(Typo.sans(13, .medium))
                                Text(status.category.label + " category").font(Typo.sans(11)).foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Button { move(status, to: index - 1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0).help("Move status left")
                            Button { move(status, to: index + 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == store.statuses.count - 1).help("Move status right")
                            Button("Rename") { editingID = status.id; name = status.name; error = nil }
                        }
                        .buttonStyle(.flat).font(Typo.sans(12)).padding(13)
                        .background(editingID == status.id ? theme.accentSoft : theme.surface)
                        .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(editingID == nil ? "Add a status" : "Rename status").font(Typo.sans(13, .semibold))
                HStack(spacing: 12) {
                    TextField("Status name", text: $name).textFieldStyle(.plain)
                        .padding(10).background(theme.field).clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit(save)
                    if editingID == nil {
                        Picker("Category", selection: $category) {
                            ForEach(TaskWorkflow.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden().frame(width: 130)
                    }
                    Button(editingID == nil ? "Add" : "Save", action: save).buttonStyle(.flat)
                        .foregroundStyle(theme.onAccent).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(theme.accent).clipShape(RoundedRectangle(cornerRadius: 6))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if editingID != nil {
                        Button("Cancel") { editingID = nil; name = ""; error = nil }.buttonStyle(.flat)
                    }
                }.font(Typo.sans(12))
                Text("Statuses in the Done category complete tasks. Renaming keeps every task in its current column.")
                    .font(Typo.sans(11)).foregroundStyle(theme.muted)
                if let error { Text(error).font(Typo.sans(12)).foregroundStyle(theme.clay) }
            }
        }
        .padding(24).frame(width: 600, height: 620).foregroundStyle(theme.text)
        .background(theme.bg).tint(theme.accentDeep).preferredColorScheme(theme.isDark ? .dark : .light)
    }
    private func save() {
        do {
            store.clearPersistenceError()
            if let editingID { try store.updateStatus(id: editingID, name: name) }
            else { _ = try store.addStatus(name: name, category: category) }
            if let failure = store.persistenceError { error = "Could not save: " + failure; return }
            editingID = nil; name = ""; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func move(_ status: TaskBoardStatus, to index: Int) {
        do { try store.updateStatus(id: status.id, position: index) }
        catch { self.error = error.localizedDescription }
    }
}
