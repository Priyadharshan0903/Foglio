// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Note: `swift test` does not work on a Command Line Tools-only install —
// CLT's `swiftpm-testing-helper` traps in `_assertionFailure` and spins
// forever. So tests are a plain executable instead: `swift run FoglioTests`
// (or `make test`). Installing Xcode would allow a normal `.testTarget`.

let package = Package(
    name: "Foglio",
    platforms: [.macOS(.v14)],
    targets: [
        // All app code lives here. Tests link this, never the executable —
        // linking an executable into a test host starts the AppKit run loop
        // and hangs the runner.
        .target(
            name: "FoglioCore",
            path: "Sources/FoglioCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Foglio",
            dependencies: ["FoglioCore"],
            path: "Sources/Foglio",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FoglioTests",
            dependencies: ["FoglioCore"],
            path: "Tests/FoglioTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
