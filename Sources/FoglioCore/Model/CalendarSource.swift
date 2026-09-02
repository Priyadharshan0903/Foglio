import Foundation
import EventKit
import Observation

/// One meeting, independent of where it came from.
struct DayEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var location: String
    var organizer: String
    var attendees: [String]
    var calendar: String

    var isPast: Bool { end < Date() }

    /// "in 25 min" / "now" / "started 10 min ago" (`relLabel`, :865).
    var relative: String {
        // Rounded, not truncated: the design compared whole clock minutes, so
        // truncating here would report a meeting 119 seconds away as "in 1 min".
        let minutes = Int((start.timeIntervalSinceNow / 60).rounded())
        if end < Date() { return "" }
        if minutes > 1 { return "in " + Self.span(minutes) }
        if minutes >= -1 { return "now" }
        return "started " + Self.span(abs(minutes)) + " ago"
    }

    static func span(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    init(
        id: String, title: String, start: Date, end: Date,
        location: String, organizer: String, attendees: [String], calendar: String
    ) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.location = location; self.organizer = organizer
        self.attendees = attendees; self.calendar = calendar
    }

    init(_ event: ICS.Event) {
        self.init(
            id: "\(event.uid)-\(event.start.timeIntervalSince1970)",
            title: event.summary.isEmpty ? "Untitled" : event.summary,
            start: event.start,
            end: event.end,
            location: event.location.isEmpty ? "No location" : event.location,
            organizer: event.organizer.isEmpty ? "—" : event.organizer,
            attendees: event.attendees,
            calendar: event.calendarName
        )
    }
}

/// Where meetings come from.
///
/// Google Workspace admins can block unapproved third-party apps outright
/// (`admin_policy_enforced`), which no OAuth client of ours can work around —
/// so OAuth is deliberately not one of these. The subscription URL is Google's
/// private iCal address: a plain HTTPS GET with a secret in the path, needing no
/// sign-in and no admin approval. A downloaded `.ics` file covers the case where
/// even that is switched off.
enum CalendarBackend: String, CaseIterable, Identifiable {
    case eventKit, subscription, file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .eventKit: "macOS Calendar"
        case .subscription: "Calendar URL"
        case .file: "Local .ics file"
        }
    }

    var hint: String {
        switch self {
        case .eventKit: "Reads accounts already added to the Calendar app"
        case .subscription: "Google Calendar ▸ Settings ▸ your calendar ▸ Secret address in iCal format"
        case .file: "Google Calendar ▸ Import & export ▸ Export. Point at the downloaded .zip, or at your Downloads folder to pick up each new export automatically."
        }
    }
}

@Observable
@MainActor
final class CalendarSource {
    enum Access: Equatable {
        case unknown, granted, denied, restricted
    }

    private(set) var access: Access = .unknown
    private(set) var events: [DayEvent] = []
    private(set) var status: String?
    private(set) var isLoading = false

    var backend: CalendarBackend = .eventKit {
        didSet {
            defaults.set(backend.rawValue, forKey: "calendarBackend")
            Task { await refresh() }
        }
    }

    var subscriptionURL: String = "" {
        didSet { defaults.set(subscriptionURL, forKey: "calendarURL") }
    }

    /// A file or a folder. A folder is re-scanned on every refresh, so a fresh
    /// export is picked up without re-choosing anything.
    private(set) var importPath: String? {
        didSet { defaults.set(importPath, forKey: "calendarImportPath") }
    }

    var importDescription: String? {
        importPath.map { ICSImporter.describe(URL(fileURLWithPath: $0)) }
    }

    /// When the export being read was produced.
    var exportedAt: Date? {
        importPath.flatMap { ICSImporter.exportedAt(URL(fileURLWithPath: $0)) }
    }

    /// A snapshot older than this probably predates a meeting you've since
    /// accepted, so the UI says so rather than looking authoritative.
    var snapshotIsStale: Bool {
        guard backend == .file, let exportedAt else { return false }
        return Date().timeIntervalSince(exportedAt) > 12 * 3600
    }

    var snapshotAge: String? {
        guard let exportedAt else { return nil }
        let seconds = Date().timeIntervalSince(exportedAt)
        if seconds < 90 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }

    /// Google's export page, so re-exporting is one click from here.
    static let googleExportURL = URL(string: "https://calendar.google.com/calendar/u/0/r/settings/export")!

    // @ObservationIgnored: the macro turns stored properties into computed
    // ones, which rules out `lazy`, and a file watcher isn't view state anyway.
    @ObservationIgnored private var watcher: FolderWatcher?

    private func startWatching(_ url: URL) {
        if watcher == nil {
            watcher = FolderWatcher { [weak self] in
                guard let self, self.backend == .file else { return }
                Task { await self.refresh() }
            }
        }
        watcher?.watch(url)
    }

    private let store = EKEventStore()
    private let defaults = UserDefaults.standard

    init() {
        if let raw = defaults.string(forKey: "calendarBackend"),
           let saved = CalendarBackend(rawValue: raw) {
            backend = saved
        }
        subscriptionURL = defaults.string(forKey: "calendarURL") ?? ""
        importPath = defaults.string(forKey: "calendarImportPath")
    }

    // MARK: - Entry points

    /// The span currently loaded. The calendar shows a week at a time, so
    /// everything works in ranges; a single day is just a one-day range.
    private(set) var range: DateInterval = CalendarSource.week(containing: Date())

    static func week(containing date: Date) -> DateInterval {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday, as work weeks are read
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
        return DateInterval(start: start, duration: 7 * 24 * 3600)
    }

    func refresh(for day: Date = Date()) async {
        await refresh(range: CalendarSource.week(containing: day))
    }

    func refresh(range: DateInterval) async {
        self.range = range
        switch backend {
        case .eventKit:
            refreshAccess()
            reloadFromEventKit(range)
        case .subscription:
            await reloadFromURL(range)
        case .file:
            reloadFromCachedFile(range)
        }
    }

    /// Events falling on one day of the loaded range.
    func events(on day: Date) -> [DayEvent] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    var todaysEvents: [DayEvent] { events(on: Date()) }

    // MARK: - EventKit

    func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .denied: access = .denied
        case .restricted: access = .restricted
        default: access = .unknown
        }
    }

    func requestAccess(for day: Date = Date()) async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        access = granted ? .granted : .denied
        if granted { reloadFromEventKit(CalendarSource.week(containing: day)) }
    }

    private func reloadFromEventKit(_ range: DateInterval) {
        guard access == .granted else { events = []; return }

        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                DayEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    location: event.location?.isEmpty == false ? event.location! : "No location",
                    organizer: event.organizer?.name ?? "—",
                    attendees: event.attendees?.compactMap(\.name) ?? [],
                    calendar: event.calendar?.title ?? "Calendar"
                )
            }
        status = events.isEmpty ? "Nothing scheduled this week." : nil
    }

    // MARK: - Subscription URL

    /// Cleans up a pasted address.
    ///
    /// `.whitespaces` was the bug here — it leaves newlines behind, and copying
    /// from Google's settings page very often brings a trailing one, which made
    /// `URL(string:)` fail or produce a mangled path.
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'"))
        // Google offers the same address as webcal://; that's just https.
        if text.hasPrefix("webcal://") {
            text = "https://" + text.dropFirst("webcal://".count)
        }
        return text
    }

    private func reloadFromURL(_ range: DateInterval) async {
        let normalized = Self.normalize(subscriptionURL)
        guard !normalized.isEmpty else {
            events = []
            status = "Paste your calendar's secret iCal address to get started."
            return
        }
        guard let url = URL(string: normalized), url.scheme?.hasPrefix("http") == true else {
            events = []
            status = "That doesn't look like a URL. It should start with https:// and end in .ics"
            return
        }

        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        // Some CDNs reject an empty User-Agent outright.
        request.setValue("Foglio/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                events = []
                status = Self.explain(status: http.statusCode, url: normalized)
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                events = []
                status = "That address returned something that isn't text."
                return
            }
            // An HTML login page comes back 200 — catch it rather than parsing
            // it into zero events and calling the day empty.
            guard text.contains("BEGIN:VCALENDAR") else {
                events = []
                status = "That address returned a web page, not a calendar feed. Make sure you copied the iCal address ending in .ics"
                return
            }
            cache(text)
            apply(text, in: range)
        } catch {
            events = []
            status = "Couldn't reach the calendar: \(error.localizedDescription)"
        }
    }

    /// Turns an HTTP status into something actionable. A bare "404" sends people
    /// hunting in the wrong place — with Google it nearly always means the
    /// *public* address was copied instead of the secret one.
    static func explain(status code: Int, url: String) -> String {
        let looksSecret = url.contains("/private-")

        switch code {
        case 404 where !looksSecret:
            return "404 — that looks like the Public address, which only works if the calendar is public. Use Settings ▸ Settings for my calendars ▸ [your calendar] ▸ Integrate calendar ▸ Secret address in iCal format. The right one has \"private-\" in it."
        case 404:
            return "404 — the address has \"private-\" in it but Google didn't recognise it. It may have been reset (Google invalidates the old one), or your admin has disabled external sharing for this calendar."
        case 401, 403:
            return "\(code) — access refused. Your organisation may have disabled sharing this calendar outside Google."
        default:
            return "The calendar server returned \(code)."
        }
    }

    // MARK: - Local file

    func chooseImport(at url: URL) {
        importPath = url.path
        startWatching(url)
        reloadFromCachedFile(range)
    }

    /// Re-arms the folder watch after a relaunch.
    func resumeWatching() {
        guard backend == .file, let path = importPath else { return }
        startWatching(URL(fileURLWithPath: path))
    }

    /// Re-reads the chosen path every time, so re-exporting into a watched
    /// folder is enough to bring the calendar up to date.
    private func reloadFromCachedFile(_ range: DateInterval) {
        guard let path = importPath else {
            events = []
            status = "Export your calendar from Google, then choose the .zip — or your Downloads folder."
            return
        }
        do {
            let text = try ICSImporter.read(URL(fileURLWithPath: path))
            cache(text)
            apply(text, in: range)
        } catch {
            events = []
            status = error.localizedDescription
        }
    }

    private var cacheURL: URL {
        Store.defaultRoot().appendingPathComponent("calendar.ics")
    }

    private func cache(_ text: String) {
        try? FileManager.default.createDirectory(
            at: Store.defaultRoot(), withIntermediateDirectories: true
        )
        try? text.write(to: cacheURL, atomically: true, encoding: .utf8)
    }

    private func apply(_ text: String, in range: DateInterval) {
        events = ICS.events(from: text, in: range).map(DayEvent.init)
        status = events.isEmpty ? "Nothing scheduled this week." : nil
    }

    // MARK: - Derived

    /// The next meeting that hasn't finished — drives the bar badge (:857).
    var upNext: DayEvent? {
        todaysEvents.first { $0.end >= Date() }
    }

    /// Whole minutes until the next meeting starts; negative once under way.
    var minutesUntilNext: Int? {
        upNext.map { Int(($0.start.timeIntervalSinceNow / 60).rounded()) }
    }

    /// The bar badge: "now", "8m", "2h" (`badgeText`, :860).
    var badgeText: String? {
        guard let minutes = minutesUntilNext else { return nil }
        if minutes <= 0 { return "now" }
        return minutes < 60 ? "\(minutes)m" : "\(Int((Double(minutes) / 60).rounded()))h"
    }

    /// Whether the next meeting is close enough to interrupt for.
    func isMeetingSoon(within lead: Int) -> Bool {
        guard let minutes = minutesUntilNext, let event = upNext else { return false }
        return minutes <= lead && event.end >= Date()
    }

    /// Distinct calendars in today's events, with counts (:943).
    var calendarCounts: [(name: String, count: Int)] {
        Dictionary(grouping: events, by: \.calendar)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0 < $1.0 }
    }

    /// True when the chosen backend still needs the user to do something.
    var needsSetup: Bool {
        switch backend {
        case .eventKit: access != .granted
        case .subscription: subscriptionURL.trimmingCharacters(in: .whitespaces).isEmpty
        case .file: importPath == nil
        }
    }
}
