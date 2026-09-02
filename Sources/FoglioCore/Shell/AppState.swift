import SwiftUI
import Observation

enum Section: String, CaseIterable, Identifiable {
    case capture, notes, tasks, calendar, settings, roadmap, week

    var id: String { rawValue }

    var label: String {
        switch self {
        case .capture: "Quick capture"
        case .notes: "Notes"
        case .tasks: "Tasks"
        case .calendar: "Calendar"
        case .settings: "Settings"
        case .roadmap: "Roadmap"
        case .week: "Weekly review"
        }
    }

    var icon: Icon {
        switch self {
        case .capture: .capture
        case .notes: .notes
        case .tasks: .tasks
        case .calendar: .week
        case .settings: .settings
        case .roadmap: .roadmap
        case .week: .chart
        }
    }

    /// The five that appear on the floating bar (`nav`, Day Log.dc.html:873).
    static let barItems: [Section] = [.capture, .notes, .tasks, .calendar, .settings]

    /// The bar's five plus the two the rail adds (`railExtra`, :880).
    static let railItems: [Section] = barItems + [.roadmap, .week]
}

/// Which screen edge the strip is docked to.
///
/// Top docks horizontally — a vertical strip along the top would eat the menu
/// bar's width and read as a mistake.
enum BarEdge: String, CaseIterable, Identifiable {
    case left, right, top

    var id: String { rawValue }
    var label: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        }
    }
    var isHorizontal: Bool { self == .top }

    /// Where a bar dropped with its centre at `center` should dock.
    ///
    /// Left and right are the default homes; top is only chosen inside a band
    /// near the top. Taking the numerically nearest of the three edges sent a
    /// bar dropped mid-screen to the top — a screen is much wider than it is
    /// tall, so the top edge is nearly always "closest" by that measure, which
    /// isn't what nearest means to someone looking at it.
    static func docking(for center: CGPoint, in visible: CGRect) -> BarEdge {
        let topBand = min(180, visible.height * 0.2)
        if visible.maxY - center.y < topBand { return .top }
        return center.x < visible.midX ? .left : .right
    }
}

enum ThemeMode: String {
    case light, dark

    var theme: Theme { self == .dark ? .dark : .light }
}

@Observable
final class AppState {
    var section: Section = .notes
    var search: String = ""

    // Notes UI state, mirroring the design's `folder` / `activeNote` /
    // `activeBlock` (Day Log.dc.html:644). `folderFilter == nil` is "All notes".
    var folderFilter: Folder?
    var activeNoteId: UUID?
    var activeBlock: Int?
    var moreOpen = false
    var pinOpen = false

    /// The bar's always-there quick-notes note, found by this id rather than
    /// by title — so renaming or reorganizing it in the full Notes UI can't
    /// orphan the bar's link to it.
    var quickNoteId: UUID = UUID() {
        didSet { defaults.set(quickNoteId.uuidString, forKey: "quickNoteId") }
    }

    /// The Notes button's live frame within the bar's own content, in
    /// SwiftUI's top-down local space — so the quick-notes card's pointer can
    /// aim at the actual icon rather than the middle of the whole strip.
    /// Deliberately not persisted: it's re-measured on every layout.
    var notesIconFrame: CGRect = .zero

    // Quick capture / Tasks draft row (:695)
    var draft: String = ""
    var draftLane: Lane = .priority

    /// Bumped to ask the window to put the caret in the search field (⌘K).
    var searchFocusRequests = 0

    /// Selected milestone on the Roadmap (`activeMs`, :695).
    var activeMilestone: Int = 1
    /// Selected event on the Calendar day timeline.
    var selectedEventId: String?

    /// How early the bar starts nudging about a meeting (`leadTime`, :861).
    var meetingLeadMinutes: Int = 10 {
        didSet { defaults.set(meetingLeadMinutes, forKey: "meetingLead") }
    }

    /// Meetings whose alert has been dismissed.
    ///
    /// Per event, not a single flag: the design's `dismissAlert` (:927) set one
    /// boolean, so dismissing one nudge silently killed every later one for the
    /// rest of the session.
    var dismissedMeetings: Set<String> = []

    func dismissMeeting(_ id: String) { dismissedMeetings.insert(id) }

    var themeMode: ThemeMode = .light { didSet { defaults.set(themeMode.rawValue, forKey: "theme") } }
    var barEdge: BarEdge = .left { didSet { defaults.set(barEdge.rawValue, forKey: "barEdge") } }
    /// Where along that edge it sits, as a fraction (0 = top/left end).
    var barOffset: Double = 0.5 { didSet { defaults.set(barOffset, forKey: "barOffset") } }
    var autoLog: Bool = true { didSet { defaults.set(autoLog, forKey: "autoLog") } }

    var theme: Theme { themeMode.theme }

    private let defaults = UserDefaults.standard

    init() {
        if let raw = defaults.string(forKey: "theme"), let m = ThemeMode(rawValue: raw) {
            themeMode = m
        }
        if let raw = defaults.string(forKey: "barEdge"), let edge = BarEdge(rawValue: raw) {
            barEdge = edge
        }
        if defaults.object(forKey: "barOffset") != nil {
            barOffset = defaults.double(forKey: "barOffset")
        }
        if defaults.object(forKey: "meetingLead") != nil {
            meetingLeadMinutes = defaults.integer(forKey: "meetingLead")
        }
        if defaults.object(forKey: "autoLog") != nil {
            autoLog = defaults.bool(forKey: "autoLog")
        }
        if let raw = defaults.string(forKey: "quickNoteId"), let id = UUID(uuidString: raw) {
            quickNoteId = id
        } else {
            defaults.set(quickNoteId.uuidString, forKey: "quickNoteId")
        }
    }
}
