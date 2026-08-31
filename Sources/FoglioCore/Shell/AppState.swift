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

enum BarSide: String {
    case left, right
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

    // Quick capture / Tasks draft row (:695)
    var draft: String = ""
    var draftLane: Lane = .priority

    /// Bumped to ask the window to put the caret in the search field (⌘K).
    var searchFocusRequests = 0

    /// Selected milestone on the Roadmap (`activeMs`, :695).
    var activeMilestone: Int = 1
    /// Selected event on the Calendar day timeline.
    var selectedEventId: String?

    // Focus timer (Day Log.dc.html:713)
    var focusMinutes: Int = 25 { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    var secondsRemaining: Int = 25 * 60
    var timerRunning: Bool = false
    var blocksCompleted: Int = 0

    var themeMode: ThemeMode = .light { didSet { defaults.set(themeMode.rawValue, forKey: "theme") } }
    var barSide: BarSide = .left { didSet { defaults.set(barSide.rawValue, forKey: "barSide") } }
    var autoLog: Bool = true { didSet { defaults.set(autoLog, forKey: "autoLog") } }

    var theme: Theme { themeMode.theme }

    private let defaults = UserDefaults.standard

    init() {
        if let raw = defaults.string(forKey: "theme"), let m = ThemeMode(rawValue: raw) {
            themeMode = m
        }
        if let raw = defaults.string(forKey: "barSide"), let s = BarSide(rawValue: raw) {
            barSide = s
        }
        if defaults.object(forKey: "focusMinutes") != nil {
            focusMinutes = defaults.integer(forKey: "focusMinutes")
        }
        if defaults.object(forKey: "autoLog") != nil {
            autoLog = defaults.bool(forKey: "autoLog")
        }
        secondsRemaining = focusMinutes * 60
    }

    var mmss: String {
        "\(secondsRemaining / 60):" + String(format: "%02d", secondsRemaining % 60)
    }

    func toggleTimer() { timerRunning.toggle() }

    /// One tick of the focus countdown. Returns true when a block just completed,
    /// so the caller can write the "Focus block complete" log entry (:717).
    @discardableResult
    func tick() -> Bool {
        guard timerRunning else { return false }
        if secondsRemaining <= 1 {
            secondsRemaining = focusMinutes * 60
            timerRunning = false
            blocksCompleted += 1
            return true
        }
        secondsRemaining -= 1
        return false
    }
}
