import SwiftUI
import UniformTypeIdentifiers

/// Hover previews placement; the store changes only when a drop is committed.
struct TaskInsertionTarget: ViewModifier {
    let taskID: UUID
    let draggedID: UUID?
    let theme: Theme
    let onDrop: (UUID, Bool) -> Void
    @State private var height: CGFloat = 1
    @State private var insertAfter: Bool?

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear { height = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, value in height = value }
                }
            }
            .overlay {
                if draggedID != nil, let insertAfter {
                    Rectangle().fill(theme.accent).frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: insertAfter ? .bottom : .top)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .onDrop(of: [UTType.text.identifier], delegate: TaskInsertionDelegate(
                taskID: taskID, draggedID: draggedID, height: height,
                insertAfter: $insertAfter, onDrop: onDrop))
            .onChange(of: draggedID) { _, _ in insertAfter = nil }
    }
}

private struct TaskInsertionDelegate: DropDelegate {
    let taskID: UUID
    let draggedID: UUID?
    let height: CGFloat
    @Binding var insertAfter: Bool?
    let onDrop: (UUID, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool { draggedID != nil && info.hasItemsConforming(to: [UTType.text.identifier]) }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { insertAfter = nil }
    func performDrop(info: DropInfo) -> Bool {
        insertAfter = nil
        guard let draggedID else { return false }
        // Dropping onto the original card is a no-op, rather than a column drop.
        if draggedID != taskID { onDrop(draggedID, info.location.y >= height / 2) }
        return true
    }
    private func update(_ info: DropInfo) {
        insertAfter = draggedID == taskID ? nil : info.location.y >= height / 2
    }
}
