import Foundation

/// A minimal test runner for the app's features.
///
/// Why not Swift Testing or XCTest: with only the Command Line Tools (no
/// Xcode, which day-to-day development does not need, ADR 0007), `swift test`
/// builds the test bundle but discovers and runs no tests. Each feature's
/// tests are an executable that calls `Checks.run`; `make macos-test` runs
/// them. Found 2026-10-19 with Swift 6.3.3.
@MainActor
public enum Checks {
    public typealias Body = @MainActor () async throws -> Void

    private static var failures: [String] = []
    private static var current = ""

    /// Records a failure without stopping the test.
    public static func expect(
        _ condition: Bool, _ message: @autoclosure () -> String = "",
        file: StaticString = #fileID, line: UInt = #line
    ) {
        if condition { return }
        failures.append("\(current): \(file):\(line) \(message())")
    }

    /// Runs every test, prints one line per test and returns the exit code.
    public static func run(_ tests: [(name: String, body: Body)]) async -> Int32 {
        var failedTests = 0
        for test in tests {
            current = test.name
            let before = failures.count
            do {
                try await test.body()
            } catch {
                failures.append("\(test.name): threw \(error)")
            }
            let passed = failures.count == before
            if !passed { failedTests += 1 }
            print("\(passed ? "ok  " : "FAIL") \(test.name)")
        }
        for failure in failures { print("  \(failure)") }
        print("\(tests.count - failedTests)/\(tests.count) passed")
        return failedTests == 0 ? 0 : 1
    }
}

@MainActor
public func expect(
    _ condition: Bool, _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID, line: UInt = #line
) {
    Checks.expect(condition, message(), file: file, line: line)
}
