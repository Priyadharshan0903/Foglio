import SwiftUI

/// Entries per day for the last week, plus three summary tiles
/// (Day Log.dc.html:591-618).
struct WeekView: View {
    @Bindable var state: AppState
    let store: Store

    private var theme: Theme { state.theme }

    private var summary: WeekSummary {
        WeekSummary.build(log: store.log, noteCount: store.notes.count)
    }

    var body: some View {
        let week = summary

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly review")
                        .font(Typo.sans(19, .semibold))
                        .kerning(-0.3)
                        .foregroundStyle(theme.text)
                    Text("Entries per day, and where the week actually went.")
                        .font(Typo.sans(12.5))
                        .foregroundStyle(theme.muted)
                }

                chart(week)
                tiles(week)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26).padding(.bottom, 34)
        }
        .background(theme.bg)
    }

    private func chart(_ week: WeekSummary) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(week.days) { day in
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("\(day.count)")
                        .font(Typo.mono(11))
                        .foregroundStyle(theme.muted)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(week.isPeak(day) ? theme.accent : theme.line)
                        .frame(height: week.barHeight(for: day))
                    Text(day.label)
                        .font(Typo.sans(11))
                        .foregroundStyle(day.isToday ? theme.text : theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 178)
        .padding(20)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }

    private func tiles(_ week: WeekSummary) -> some View {
        HStack(spacing: 12) {
            tile(
                value: week.entries,
                label: "Entries logged",
                color: theme.text,
                note: "Notes and finished tasks."
            )
            tile(
                value: week.notes,
                label: "Notes",
                color: theme.ok,
                note: "Across \(Set(store.notes.map(\.folder)).count) folders."
            )
        }
    }

    private func tile(value: Int, label: String, color: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(Typo.sans(27, .semibold))
                .kerning(-0.54)
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(Typo.sans(10.5))
                .kerning(1.47)
                .foregroundStyle(theme.muted)
                .padding(.top, 6)
            Text(note)
                .font(Typo.sans(12))
                .foregroundStyle(theme.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }
}
