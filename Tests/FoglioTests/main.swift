@testable import FoglioCore

designTokenTests()
markdownTests()
notesTests()
weekTests()
icsTests()
importerTests()
MainActor.assumeIsolated { calendarURLTests() }
MainActor.assumeIsolated { storeTests() }
MainActor.assumeIsolated { renameTests() }
MainActor.assumeIsolated { tasksTests() }
MainActor.assumeIsolated { exportTests() }

Check.finish()
