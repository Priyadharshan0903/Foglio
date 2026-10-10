import SwiftUI

/// Native segmented pickers can use the macOS accent instead of the app's
/// palette. Own the styling so selection, hover and keyboard focus agree.
struct TaskStatusFilter: View {
    @Binding var selection: TaskStatus
    let counts: [TaskStatus: Int]
    let theme: Theme

    @FocusState private var focusedStatus: TaskStatus?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(TaskStatus.allCases) { status in
                segment(status)
            }
        }
        .padding(4)
        .background(theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter tasks by status")
        .onMoveCommand { direction in
            let statuses = TaskStatus.allCases
            guard let current = statuses.firstIndex(of: focusedStatus ?? selection) else { return }
            let index: Int
            switch direction {
            case .left: index = max(0, current - 1)
            case .right: index = min(statuses.count - 1, current + 1)
            default: return
            }
            focusedStatus = statuses[index]
            selection = statuses[index]
        }
    }

    private func segment(_ status: TaskStatus) -> some View {
        let selected = selection == status
        return Button { selection = status } label: {
            HStack(spacing: 7) {
                Text(status.label)
                    .font(Typo.sans(12, selected ? .semibold : .medium))
                Text("\(counts[status, default: 0])")
                    .font(Typo.mono(10.5))
            }
            .foregroundStyle(selected ? theme.onAccent : theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(selected ? theme.accent : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .hoverHighlight(theme, cornerRadius: 6, active: !selected)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(focusedStatus == status ? theme.accentDeep : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.flat)
        .focused($focusedStatus, equals: status)
        .focusEffectDisabled()
        .accessibilityLabel("\(status.label), \(counts[status, default: 0]) tasks")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("task-status-\(status.rawValue)")
        .help("Show \(status.label.lowercased()) tasks")
    }
}
