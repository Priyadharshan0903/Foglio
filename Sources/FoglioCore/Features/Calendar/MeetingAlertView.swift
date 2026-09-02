import SwiftUI

/// The nudge that appears beside the bar before a meeting (Day Log.dc.html:70-84).
struct MeetingAlertView: View {
    @Bindable var state: AppState
    let event: DayEvent
    var onJoin: () -> Void
    var onTakeNotes: () -> Void
    var onDismiss: () -> Void

    private var theme: Theme { state.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("STARTING \(event.relative.replacingOccurrences(of: "in ", with: "IN ").uppercased())")
                    .font(Typo.sans(10))
                    .kerning(1.4)
                    .foregroundStyle(theme.clay)
                Spacer()
                Button(action: onDismiss) {
                    Text("×")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.muted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.flat)
                .help("Dismiss this reminder")
            }

            Text(event.title)
                .font(Typo.sans(15, .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Text("\(Clock.hhmm(event.start))–\(Clock.hhmm(event.end))")
                .font(Typo.sans(12))
                .foregroundStyle(theme.muted)
                .padding(.top, 4)

            Text(event.attendees.isEmpty
                 ? event.location
                 : "\(event.location) · \(event.attendees.prefix(3).joined(separator: ", "))")
                .font(Typo.sans(12))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .padding(.top, 2)

            HStack(spacing: 6) {
                if joinURL != nil {
                    Button(action: onJoin) {
                        Text("Join")
                            .font(Typo.sans(11.5, .semibold))
                            .foregroundStyle(theme.onAccent)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.flat)
                }

                Button(action: onTakeNotes) {
                    Text("Take notes")
                        .font(Typo.sans(11.5, .medium))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.flat)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
        .frame(width: 288, alignment: .leading)
        .background(theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }

    /// A conferencing link if the event carries one.
    ///
    /// The design's Join button always showed; here it only appears when there's
    /// somewhere to go, since a button that does nothing is worse than no button.
    var joinURL: URL? { MeetingAlertView.joinURL(for: event) }

    static func joinURL(for event: DayEvent) -> URL? {
        // Calendar entries put the link in the location, sometimes with other
        // text around it.
        let haystack = event.location
        guard let range = haystack.range(
            of: #"https?://[^\s,;]+"#,
            options: .regularExpression
        ) else { return nil }

        let candidate = String(haystack[range])
        let known = ["meet.google.com", "zoom.us", "teams.microsoft.com", "webex.com"]
        guard known.contains(where: candidate.contains) else { return nil }
        return URL(string: candidate)
    }
}
