import SwiftUI

/// Milestones on a progress track, the active milestone's steps, and any notes
/// pinned to it (Day Log.dc.html:534-589).
struct RoadmapView: View {
    @Bindable var state: AppState
    let store: Store

    private var theme: Theme { state.theme }

    private var milestones: [Milestone] { store.milestones }

    private var active: Milestone? {
        guard !milestones.isEmpty else { return nil }
        return milestones[min(state.activeMilestone, milestones.count - 1)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Career roadmap")
                        .font(Typo.sans(19, .semibold))
                        .kerning(-0.3)
                        .foregroundStyle(theme.text)
                    Text("Notes pinned to a milestone show up here.")
                        .font(Typo.sans(12.5))
                        .foregroundStyle(theme.muted)
                }

                track

                HStack(alignment: .top, spacing: 16) {
                    activeCard
                    pinnedCard.frame(width: 300)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 26).padding(.bottom, 34)
        }
        .background(theme.bg)
    }

    // MARK: - Track

    private var track: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                    Button { state.activeMilestone = index } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(milestone.when.uppercased())
                                .font(Typo.sans(10))
                                .kerning(1.4)
                                .foregroundStyle(theme.muted)
                            Text(milestone.title)
                                .font(Typo.sans(13.5, .medium))
                                .foregroundStyle(index == state.activeMilestone ? theme.text : theme.muted)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10).padding(.trailing, 14)
                    }
                    .buttonStyle(.flat)
                }
            }

            // The rail, its filled portion, and a node per milestone.
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    let inset = geo.size.width * 0.04
                    let span = geo.size.width - inset * 2

                    Rectangle()
                        .fill(theme.line)
                        .frame(width: span, height: 2)
                        .offset(x: inset, y: 5.5)

                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: span * progress, height: 2)
                        .offset(x: inset, y: 5.5)
                }

                HStack(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.element.id) { index, _ in
                        let isActive = index == state.activeMilestone
                        Circle()
                            .fill(isActive ? theme.accent : theme.bg)
                            .frame(width: 13, height: 13)
                            .overlay(
                                Circle().strokeBorder(isActive ? theme.accent : theme.muted, lineWidth: 2)
                            )
                            .overlay(Circle().strokeBorder(theme.surface, lineWidth: 5).scaleEffect(1.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 10)
                    }
                }
            }
            .frame(height: 13)
            .padding(.top, 16)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24).padding(.bottom, 20)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }

    /// Share of every step across every milestone that is done (:1167).
    private var progress: CGFloat {
        let all = milestones.flatMap(\.steps)
        guard !all.isEmpty else { return 0 }
        return CGFloat(all.filter(\.done).count) / CGFloat(all.count)
    }

    // MARK: - Active milestone

    @ViewBuilder
    private var activeCard: some View {
        if let milestone = active {
            VStack(alignment: .leading, spacing: 0) {
                Text(milestone.when.uppercased())
                    .font(Typo.sans(10))
                    .kerning(1.6)
                    .foregroundStyle(theme.muted)
                Text(milestone.title)
                    .font(Typo.sans(17, .semibold))
                    .foregroundStyle(theme.text)
                    .padding(.top, 5)
                Text(milestone.goal)
                    .font(Typo.sans(13))
                    .foregroundStyle(theme.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                ForEach(milestone.steps) { step in
                    HStack(spacing: 11) {
                        Button {
                            store.toggleStep(milestoneId: milestone.id, stepId: step.id)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(step.done ? theme.ok : .clear)
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(step.done ? theme.ok : theme.muted, lineWidth: 1.5)
                                if step.done {
                                    Text("✓").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(theme.bg)
                                }
                            }
                            .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.flat)

                        StrikeText(
                            text: step.label,
                            struck: step.done,
                            font: Typo.sans(13),
                            color: step.done ? theme.muted : theme.text,
                            strikeColor: theme.ok
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.line, lineWidth: 1)
            )
        }
    }

    // MARK: - Pinned notes

    private var pinnedCard: some View {
        let pinned = store.notes.filter { $0.pin == active?.title }

        return VStack(alignment: .leading, spacing: 0) {
            Text("NOTES PINNED HERE")
                .font(Typo.sans(10))
                .kerning(1.6)
                .foregroundStyle(theme.muted)

            if pinned.isEmpty {
                Text("Nothing pinned yet — open a note and use the pin button under its title.")
                    .font(Typo.sans(12))
                    .foregroundStyle(theme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(pinned) { note in
                        Button {
                            state.section = .notes
                            state.activeNoteId = note.id
                            state.activeBlock = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title.isEmpty ? "Untitled note" : note.title)
                                    .font(Typo.sans(12.5, .medium))
                                    .foregroundStyle(theme.text)
                                Text(note.snippet)
                                    .font(Typo.sans(11))
                                    .foregroundStyle(theme.muted)
                                    .lineLimit(2)
                                    .lineSpacing(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(theme.field)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.flat)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }
}
