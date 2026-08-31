import Foundation

// A deliberately tiny test harness.
//
// `swift test` is unusable here: this machine has Command Line Tools but no
// Xcode, and CLT's `swiftpm-testing-helper` traps in `_assertionFailure` and
// spins forever instead of running anything. Rather than make Xcode a
// prerequisite, the test target is a plain executable — `swift run FoglioTests`
// — with the handful of assertions we actually need.

enum Check {
    nonisolated(unsafe) static var passed = 0
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) private static var suite = ""

    static func suite(_ name: String, _ body: () -> Void) {
        suite = name
        print("\n\(name)")
        body()
    }

    static func expect(
        _ condition: Bool,
        _ message: @autoclosure () -> String,
        line: UInt = #line
    ) {
        if condition {
            passed += 1
            print("  ok   \(message())")
        } else {
            let text = "\(suite): \(message())  [line \(line)]"
            failures.append(text)
            print("  FAIL \(message())  [line \(line)]")
        }
    }

    static func equal<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: @autoclosure () -> String,
        line: UInt = #line
    ) {
        if actual == expected {
            passed += 1
            print("  ok   \(message())")
        } else {
            let text = "\(suite): \(message())\n         expected: \(expected)\n         actual:   \(actual)  [line \(line)]"
            failures.append(text)
            print("  FAIL \(message())")
            print("       expected: \(expected)")
            print("       actual:   \(actual)  [line \(line)]")
        }
    }

    static func finish() -> Never {
        print("\n" + String(repeating: "-", count: 52))
        if failures.isEmpty {
            print("\(passed) passed, 0 failed")
            exit(0)
        }
        print("\(passed) passed, \(failures.count) FAILED\n")
        for f in failures { print("  - \(f)") }
        exit(1)
    }
}
