import SwiftUI
import AppKit

/// Meeting details, opened by clicking an event in the week grid.
///
/// Replaces the design's fixed side panel (:409-443): with seven days on screen
/// there isn't room for a permanent inspector, and a sheet gives the details far
/// more space than a 288pt column did.
struct EventDetailSheet: View {
    @Bindable var state: AppState
    let event: DayEvent
    var onTakeNotes: () -> Void
    var onAddFollowUp: () -> Void
    var onClose: () -> Void

    private var theme: Theme { state.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(theme.line)

            VStack(alignment: .leading, spacing: 14) {
                row("When", value: whenText, mono: false)
                row("Where", value: event.location, mono: false)
                row("Calendar", value: event.calendar, mono: false)
                row("Organizer", value: event.organizer, mono: false)
                if !event.attendees.isEmpty { guests }
            }
            .padding(.horizontal, 22).padding(.vertical, 18)

            Divider().overlay(theme.line)
            actions
        }
        .frame(width: 420)
        .background(theme.bg)
        .environment(\.theme, theme)
        .preferredColorScheme(state.themeMode == .dark ? .dark : .light)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.isPast ? theme.muted : theme.accent)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(Typo.sans(17, .semibold))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !event.relative.isEmpty {
                    Text(event.relative)
                        .font(Typo.sans(12))
                        .foregroundStyle(theme.accentDeep)
                }
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Text("×")
                    .font(.system(size: 17))
                    .foregroundStyle(theme.muted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.flat)
            .help("Close")
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var whenText: String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_GB")
        day.dateFormat = "EEEE d MMMM"
        return "\(day.string(from: event.start))  ·  \(Clock.hhmm(event.start))–\(Clock.hhmm(event.end))"
    }

    private func row(_ label: String, value: String, mono: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(Typo.sans(11))
                .foregroundStyle(theme.muted)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(mono ? Typo.mono(12.5) : Typo.sans(12.5))
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var guests: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("Guests")
                .font(Typo.sans(11))
                .foregroundStyle(theme.muted)
                .frame(width: 70, alignment: .leading)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(event.attendees, id: \.self) { name in
                    HStack(spacing: 6) {
                        Text(String(name.prefix(1)).uppercased())
                            .font(Typo.sans(9.5, .semibold))
                            .foregroundStyle(theme.accentDeep)
                            .frame(width: 18, height: 18)
                            .background(theme.accentSoft)
                            .clipShape(Circle())
                        Text(name).font(Typo.sans(11.5)).foregroundStyle(theme.text)
                    }
                    .padding(.leading, 3).padding(.trailing, 8).padding(.vertical, 3)
                    .background(theme.field)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let url = MeetingAlertView.joinURL(for: event) {
                Button { NSWorkspace.shared.open(url) } label: {
                    pill("Join", filled: true)
                }
                .buttonStyle(.flat)
            }
            Button(action: onTakeNotes) { pill("Take notes", filled: false) }
                .buttonStyle(.flat)
            Button(action: onAddFollowUp) { pill("Add follow-up", filled: false) }
                .buttonStyle(.flat)
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(theme.surface)
    }

    private func pill(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(Typo.sans(12, filled ? .semibold : .medium))
            .foregroundStyle(filled ? theme.onAccent : theme.text)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(filled ? theme.accent : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(filled ? .clear : theme.line, lineWidth: 1)
            )
    }
}
