import SwiftUI

/// One input that becomes either a task or a log entry, over today's log
/// (Day Log.dc.html:280-310).
struct CaptureView: View {
    @Bindable var state: AppState
    let store: Store

    private var theme: Theme { state.theme }

    /// Same reasoning as TasksView: the search box names the log, so it filters it.
    private var visibleLog: [LogEntry] {
        let query = state.search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return store.todaysLog }
        return store.todaysLog.filter { $0.text.lowercased().contains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick capture")
                        .font(Typo.sans(19, .semibold))
                        .kerning(-0.3)
                        .foregroundStyle(theme.text)
                    Text("A task if it's next, a log entry if it's done.")
                        .font(Typo.sans(12.5))
                        .foregroundStyle(theme.muted)
                }

                inputRow
                laneRow
                todaySection
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 26).padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bg)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Type it and hit return…", text: $state.draft)
                .textFieldStyle(.plain)
                .font(Typo.sans(14))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 13).padding(.vertical, 12)
                .background(theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.line, lineWidth: 1)
                )
                .onSubmit(addTask)

            Button(action: addTask) {
                Text("Add task")
                    .font(Typo.sans(12.5, .semibold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 17).padding(.vertical, 12)
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.flat)

            Button(action: addLog) {
                Text("Log it")
                    .font(Typo.sans(12.5, .semibold))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 17).padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(theme.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.flat)
        }
    }

    private var laneRow: some View {
        HStack(spacing: 6) {
            ForEach(Lane.allCases) { lane in
                let selected = state.draftLane == lane
                Button { state.draftLane = lane } label: {
                    Text(lane.label)
                        .font(Typo.sans(11, .medium))
                        .foregroundStyle(selected ? theme.onAccent : theme.muted)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(selected ? theme.accent : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.flat)
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY")
                .font(Typo.sans(10))
                .kerning(1.6)
                .foregroundStyle(theme.muted)
                .padding(.bottom, 4)

            // Newest first (:1157).
            ForEach(visibleLog.reversed()) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(Clock.hhmm(entry.at))
                        .font(Typo.mono(11.5))
                        .foregroundStyle(theme.muted)
                        .frame(width: 56, alignment: .leading)

                    Text(entry.text)
                        .font(Typo.sans(13.5))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 7) {
                        Circle().fill(dotColor(entry.kind)).frame(width: 5, height: 5)
                        Text(entry.kind.rawValue.uppercased())
                            .font(Typo.sans(10))
                            .kerning(1.2)
                            .foregroundStyle(theme.muted)
                    }
                }
                .padding(.vertical, 11).padding(.horizontal, 2)
                .overlay(alignment: .top) {
                    Rectangle().fill(theme.lineSoft).frame(height: 1)
                }
            }

            if visibleLog.isEmpty {
                Text(state.search.isEmpty ? "Nothing logged yet today." : "Nothing in today's log matches.")
                    .font(Typo.sans(12))
                    .foregroundStyle(theme.muted)
                    .padding(.vertical, 12)
            }
        }
    }

    private func dotColor(_ kind: LogKind) -> Color {
        switch kind {
        case .task: theme.ok
        case .focus: theme.accent
        case .manual: theme.muted
        }
    }

    private func addTask() {
        let label = state.draft.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        store.addTask(TaskItem(
            label: label,
            lane: state.draftLane,
            meta: state.draftLane == .delegate ? "Follow up" : ""
        ))
        state.draft = ""
    }

    private func addLog() {
        let text = state.draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.addLog(LogEntry(text: text, kind: .manual))
        state.draft = ""
    }
}
