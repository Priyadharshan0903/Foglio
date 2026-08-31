@testable import FoglioCore

designTokenTests()
markdownTests()
MainActor.assumeIsolated { storeTests() }

Check.finish()
