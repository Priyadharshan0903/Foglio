@testable import FoglioCore

designTokenTests()
dockingTests()
iconAlignmentTests()
markdownTests()
notesTests()
editorPlaceholderTests()
weekTests()
icsTests()
importerTests()
MainActor.assumeIsolated { snapshotAgeTests() }
MainActor.assumeIsolated { calendarURLTests() }
MainActor.assumeIsolated { meetingNudgeTests() }
MainActor.assumeIsolated { weekRangeTests() }
MainActor.assumeIsolated { storeTests() }
MainActor.assumeIsolated { renameTests() }
MainActor.assumeIsolated { tasksTests() }
MainActor.assumeIsolated { exportTests() }

Check.finish()
