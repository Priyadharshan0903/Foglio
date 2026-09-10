@testable import FoglioCore

designTokenTests()
dockingTests()
iconAlignmentTests()
markdownTests()
notesTests()
editorPlaceholderTests()
sourceModeTests()
weekTests()
icsTests()
importerTests()
MainActor.assumeIsolated { snapshotAgeTests() }
MainActor.assumeIsolated { calendarURLTests() }
MainActor.assumeIsolated { meetingNudgeTests() }
MainActor.assumeIsolated { weekRangeTests() }
MainActor.assumeIsolated { storeTests() }
MainActor.assumeIsolated { renameTests() }
MainActor.assumeIsolated { folderTests() }
MainActor.assumeIsolated { selectionTests() }
MainActor.assumeIsolated { folderExportTests() }
MainActor.assumeIsolated { tasksTests() }
MainActor.assumeIsolated { laneTests() }
MainActor.assumeIsolated { exportTests() }

Check.finish()
