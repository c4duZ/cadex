import Checks
import Foundation
@testable import Orchestration

// Tests of the orchestration's state (docs/spec/orchestration.md, plan 24
// phase B). Run with `make macos-test`. Each test has its own SQLite file
// in a temporary folder (or ":memory:"), removed at the end.

nonisolated(unsafe) let fm = FileManager.default

func tempDir() -> String {
    let dir = NSTemporaryDirectory() + "cadex-orch-\(UUID().uuidString)"
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

/// A book on a fresh in-memory store, with ids t1, t2… and a clock the test moves.
final class Fixture {
    let book: RunBook
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var counter = 0

    init() throws {
        book = RunBook(store: try OrchestrationStore(path: ":memory:"))
        book.newId = { [unowned self] in counter += 1; return "id\(counter)" }
        book.now = { [unowned self] in clock }
    }

    func run() throws -> Run { try book.newRun(name: "r", repository: "/repo", caps: Caps(budgetUsd: 5, maxMinutes: 60)) }
    func state(_ id: String) throws -> TaskState? { (try book.store.get(.tasks, id: id) as RunTask?)?.state }
    func dispatch(_ task: String, max: Int = 6, session: String? = nil) throws -> Dispatch {
        try book.dispatch(task: task, agent: AgentChoice(), worktree: "/w/\(task)", session: session.map { SessionLink(kit: $0) }, maxAgents: max)
    }
}

let exitCode = await Checks.run(runTests + storeTests)
exit(exitCode)
