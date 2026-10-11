import SwiftUI
import UniformTypeIdentifiers

struct TaskDropPlacement: Equatable {
    let anchorID: UUID
    let after: Bool
}

struct TaskBoardDragHover: Equatable {
    let statusID: String
    let placement: TaskDropPlacement?
}

/// A projected slot changes presentation only. The Store's order is committed
/// once, on drop; cancelling needs no persistence or undo operation.
enum TaskLaneDragLayout {
    static func index(taskIDs: [UUID], sourceID: UUID, placement: TaskDropPlacement?, restoringSource: Bool = false) -> Int {
        let peers = taskIDs.filter { $0 != sourceID }
        if restoringSource, let original = taskIDs.firstIndex(of: sourceID) { return original }
        guard let placement, let anchor = peers.firstIndex(of: placement.anchorID) else { return peers.count }
        return anchor + (placement.after ? 1 : 0)
    }

    static func placement(at index: Int, taskIDs: [UUID], sourceID: UUID) -> TaskDropPlacement? {
        let peers = taskIDs.filter { $0 != sourceID }
        guard !peers.isEmpty else { return nil }
        let index = min(max(index, 0), peers.count)
        if index < peers.count { return TaskDropPlacement(anchorID: peers[index], after: false) }
        return TaskDropPlacement(anchorID: peers.last!, after: true)
    }
}

/// One hover session owns both lane highlighting and insertion feedback.
/// Geometry is resolved in the lane, including the scroll view's current offset.
struct TaskColumnDragState: Equatable {
    private(set) var sourceID: UUID?
    private(set) var location: CGPoint?
    private(set) var placement: TaskDropPlacement?

    mutating func update(sourceID: UUID, location: CGPoint, taskIDs: [UUID], frames: [UUID: CGRect], placeholder: CGRect? = nil) {
        let sameSession = self.sourceID == sourceID
        self.sourceID = sourceID
        self.location = location
        // Reflow puts a full-height gap under the cursor. Keep that slot while
        // inside it instead of repeatedly switching between its adjacent cards.
        if sameSession, let placeholder, placeholder.insetBy(dx: 0, dy: -4).contains(location) { return }
        let cards = taskIDs.compactMap { id -> (UUID, CGRect)? in
            guard id != sourceID, let frame = frames[id], frame.height > 0 else { return nil }
            return (id, frame)
        }.sorted { $0.1.minY < $1.1.minY }
        if let next = cards.first(where: { location.y <= $0.1.maxY }) {
            placement = TaskDropPlacement(anchorID: next.0, after: location.y >= next.1.midY)
        } else if let last = cards.last {
            placement = TaskDropPlacement(anchorID: last.0, after: true)
        } else {
            placement = nil
        }
    }

    mutating func clear() { self = TaskColumnDragState() }

    func indicatorY(frames: [UUID: CGRect], emptyY: CGFloat, viewport: CGRect? = nil, placeholder: CGRect? = nil) -> CGFloat {
        var y = emptyY
        // Put the line in the gap rather than across a card's text/border.
        if let placeholder {
            y = placeholder.minY - 3
        } else if let placement, let frame = frames[placement.anchorID] {
            y = placement.after ? frame.maxY + 4 : frame.minY - 4
        }
        // A partially clipped card still needs a visible guide in the task area.
        if let viewport, viewport.height > 4 {
            y = min(max(y, viewport.minY + 2), viewport.maxY - 2)
        }
        return y
    }
}

struct TaskCardBoundsKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TaskColumnViewportKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

struct TaskDropPlaceholderBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

struct TaskDropPlaceholder: View {
    let height: CGFloat
    let theme: Theme
    var body: some View {
        RoundedRectangle(cornerRadius: 8).fill(theme.accentSoft.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.accentDeep.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .frame(height: max(44, height))
            .anchorPreference(key: TaskDropPlaceholderBoundsKey.self, value: .bounds) { $0 }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct TaskColumnDropTarget: ViewModifier {
    let taskIDs: [UUID]
    let draggedID: UUID?
    let theme: Theme
    let onDrop: (UUID, TaskDropPlacement?) -> Void
    var onHover: (TaskDropPlacement?) -> Void = { _ in }
    var onExit: () -> Void = {}
    @State private var frames: [UUID: CGRect] = [:]
    @State private var viewport: CGRect?
    @State private var feedback = TaskColumnDragState()
    @State private var placeholder: CGRect?

    private var active: Bool { draggedID != nil && feedback.sourceID == draggedID }

    func body(content: Content) -> some View {
        content
            .modifier(TaskColumnDropDecoration(active: active,
                       insertionY: feedback.indicatorY(frames: frames, emptyY: (viewport?.minY ?? 48) + 4,
                                                        viewport: viewport, placeholder: placeholder), theme: theme))
            .backgroundPreferenceValue(TaskCardBoundsKey.self) { anchors in
                GeometryReader { geometry in
                    let resolved = anchors.mapValues { geometry[$0] }
                    Color.clear
                        .onAppear { updateFrames(resolved) }
                        .onChange(of: resolved) { _, new in updateFrames(new) }
                        .allowsHitTesting(false)
                }
            }
            .backgroundPreferenceValue(TaskColumnViewportKey.self) { anchor in
                GeometryReader { geometry in
                    let resolved = anchor.map { geometry[$0] }
                    Color.clear.onAppear { viewport = resolved }
                        .onChange(of: resolved) { _, new in viewport = new }
                        .allowsHitTesting(false)
                }
            }
            .backgroundPreferenceValue(TaskDropPlaceholderBoundsKey.self) { anchor in
                GeometryReader { geometry in
                    let resolved = anchor.map { geometry[$0] }
                    Color.clear.onAppear { placeholder = resolved }
                        .onChange(of: resolved) { _, new in placeholder = new }
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.text.identifier], delegate: TaskColumnDropDelegate(
                draggedID: draggedID, taskIDs: taskIDs, frames: frames, placeholder: placeholder,
                feedback: $feedback, onDrop: onDrop))
            .onChange(of: draggedID) { _, _ in feedback.clear() }
            .onChange(of: feedback) { _, new in
                if new.sourceID != nil { onHover(new.placement) } else { onExit() }
            }
    }

    private func updateFrames(_ new: [UUID: CGRect]) {
        frames = new
        if let sourceID = feedback.sourceID, let location = feedback.location {
            feedback.update(sourceID: sourceID, location: location, taskIDs: taskIDs, frames: new, placeholder: placeholder)
        }
    }
}

/// Stateless rendering also allows native previews of a simulated hover session.
struct TaskColumnDropDecoration: ViewModifier {
    let active: Bool
    let insertionY: CGFloat
    let theme: Theme
    func body(content: Content) -> some View {
        content
            .background(active ? theme.accentSoft : theme.field.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? theme.accentDeep : .clear, lineWidth: 1))
            .overlay {
                if active {
                    GeometryReader { geometry in
                        TaskColumnInsertionLine(theme: theme)
                            .frame(width: max(0, geometry.size.width - 24), height: 2)
                            .position(x: geometry.size.width / 2,
                                      y: min(max(insertionY, 12), geometry.size.height - 12))
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }
}

struct TaskColumnInsertionLine: View {
    let theme: Theme
    var body: some View {
        Capsule().fill(theme.accent)
            .overlay(alignment: .leading) { Circle().fill(theme.accent).frame(width: 6, height: 6) }
    }
}

private struct TaskColumnDropDelegate: DropDelegate {
    let draggedID: UUID?
    let taskIDs: [UUID]
    let frames: [UUID: CGRect]
    let placeholder: CGRect?
    @Binding var feedback: TaskColumnDragState
    let onDrop: (UUID, TaskDropPlacement?) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedID != nil && info.hasItemsConforming(to: [UTType.text.identifier])
    }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { feedback.clear() }
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID else { feedback.clear(); return false }
        update(info)
        let placement = feedback.placement
        feedback.clear()
        // A lane containing only the dragged card already has the correct order.
        if placement != nil || !taskIDs.contains(draggedID) { onDrop(draggedID, placement) }
        return true
    }
    private func update(_ info: DropInfo) {
        guard let draggedID else { feedback.clear(); return }
        feedback.update(sourceID: draggedID, location: info.location, taskIDs: taskIDs, frames: frames, placeholder: placeholder)
    }
}
