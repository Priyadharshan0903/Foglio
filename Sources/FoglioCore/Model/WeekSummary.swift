import Foundation

/// The numbers behind the Weekly review (Day Log.dc.html:1187-1199).
///
/// The design hardcoded its bars; these come from the real log. Kept out of the
/// view so the bucketing is testable — off-by-one day errors here are easy to
/// make and invisible on screen.
struct WeekSummary: Equatable {
    struct Day: Equatable, Identifiable {
        let id: Int
        let label: String
        let count: Int
        let isToday: Bool
    }

    var days: [Day] = []
    var entries: Int = 0
    var focusBlocks: Int = 0
    var notes: Int = 0

    /// Bar height in points, matching the design's `(value / max) * 122 + 8`.
    func barHeight(for day: Day) -> CGFloat {
        let peak = max(days.map(\.count).max() ?? 0, 1)
        return CGFloat(day.count) / CGFloat(peak) * 122 + 8
    }

    func isPeak(_ day: Day) -> Bool {
        day.count > 0 && day.count == days.map(\.count).max()
    }

    /// Seven days ending today.
    static func build(log: [LogEntry], noteCount: Int, now: Date = Date()) -> WeekSummary {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        var days: [Day] = []
        var entries = 0
        var focus = 0

        for offset in stride(from: 6, through: 0, by: -1) {
            guard let start = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let onThisDay = log.filter { cal.isDate($0.at, inSameDayAs: start) }

            entries += onThisDay.count
            focus += onThisDay.filter { $0.kind == .focus }.count

            days.append(Day(
                id: offset,
                label: offset == 0 ? "Today" : formatter.string(from: start),
                count: onThisDay.count,
                isToday: offset == 0
            ))
        }

        return WeekSummary(days: days, entries: entries, focusBlocks: focus, notes: noteCount)
    }
}
