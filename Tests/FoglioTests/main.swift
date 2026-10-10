@testable import FoglioCore
import Foundation

designTokenTests()
MainActor.assumeIsolated { themeTests() }
MainActor.assumeIsolated { themeSurfaceTests() }
dockingTests()
iconAlignmentTests()
markdownTests()
notesTests()
MainActor.assumeIsolated { continuousEditorTests() }
MainActor.assumeIsolated { richEditorTests() }
MainActor.assumeIsolated { taskWorkflowTests() }
MainActor.assumeIsolated { taskWorkspaceTests() }
MainActor.assumeIsolated { taskEditorTests() }
MainActor.assumeIsolated { attachmentTests() }
sourceModeTests()
weekTests()
datePickerTests()
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
taskListQueryTests()
MainActor.assumeIsolated { noteTypingSaveTests() }
MainActor.assumeIsolated { tasksTests() }
MainActor.assumeIsolated { laneTests() }
MainActor.assumeIsolated { trashTests() }
MainActor.assumeIsolated { exportTests() }

MainActor.assumeIsolated { renderPreviewsIfRequested() }
MainActor.assumeIsolated { renderTaskPreviewsIfRequested() }
MainActor.assumeIsolated { renderLandingAssetsIfRequested() }
connectorProtocolTests()
Task { @MainActor in
    await connectorIntegrationTests()
    Check.finish()
}
dispatchMain()
