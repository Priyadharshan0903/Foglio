import SwiftUI

/// Native text decoration keeps the strike aligned with wrapped/truncated lines.
/// Only its reveal is animated; the title's layout and stored text stay intact.
struct TaskTitle: View {
    let task: TaskItem
    let theme: Theme
    let font: Font
    let lineLimit: Int
    let animateCompletion: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var strikeProgress: CGFloat

    init(task: TaskItem, theme: Theme, font: Font, lineLimit: Int, animateCompletion: Bool = false) {
        self.task = task
        self.theme = theme
        self.font = font
        self.lineLimit = lineLimit
        self.animateCompletion = animateCompletion
        _strikeProgress = State(initialValue: task.done && !animateCompletion ? 1 : 0)
    }

    private var title: some View {
        Text(task.label).font(font)
            .foregroundStyle(task.done ? theme.muted : theme.text)
            .lineLimit(lineLimit).multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        title.overlay(alignment: .leading) {
            Text(task.label).font(font)
                .foregroundStyle(.clear)
                .strikethrough(true, color: theme.muted)
                .lineLimit(lineLimit).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .mask {
                    Rectangle().scaleEffect(x: strikeProgress, y: 1, anchor: .leading)
                }
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityValue(task.done ? "Completed" : "Open")
        .task(id: [task.done, animateCompletion, reduceMotion]) {
            // Existing completed tasks render struck immediately on opening,
            // filtering, or switching layouts. Only a fresh transition sweeps.
            let animate = task.done && animateCompletion && !reduceMotion
            withAnimation(nil) { strikeProgress = animate ? 0 : (task.done ? 1 : 0) }
            guard animate else { return }
            // Let the initial unstruck frame render before revealing the line.
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return }
            withAnimation(.easeInOut(duration: 0.32)) { strikeProgress = 1 }
        }
    }
}
