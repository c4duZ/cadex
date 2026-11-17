import Foundation

// The orchestration's records (docs/spec/orchestration.md, plan 24 phase B):
// races, runs, their tasks, dispatches and messages, automations and their
// history. Plain values, kept as JSON in the state's SQLite file
// (OrchestrationStore); the rules over them are in RunGraph.

/// Where a session opened with a prompt runs. Only a tab for now: `claude
/// --bg` was weighed in phase B (2026-11-16) and left out until a test shows
/// the kit's hooks and status line reach a background session; the field
/// stays so a run can say it later without a new table.
public enum LaunchMode: String, Codable, Sendable { case tab }

/// The caps every race, run and automation carries (ADR 0033).
public struct Caps: Codable, Equatable, Sendable {
    public var budgetUsd: Double
    public var maxMinutes: Int
    public init(budgetUsd: Double, maxMinutes: Int) {
        self.budgetUsd = budgetUsd
        self.maxMinutes = maxMinutes
    }
}

/// Who an agent runs as: the account's folder (nil is ~/.claude), the model
/// (empty is the account's default) and the machine (empty is this Mac).
public struct AgentChoice: Codable, Equatable, Sendable {
    public var account: String?
    public var model: String
    public var machine: String
    public init(account: String? = nil, model: String = "", machine: String = "") {
        self.account = account
        self.model = model
        self.machine = machine
    }
}

// MARK: Races

public struct Race: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var prompt: String
    public var repository: String
    /// The commit every contender starts from.
    public var base: String
    public var caps: Caps
    public var createdAt: Date
    public var winner: String?
    public var discarded = false
}

public enum ContenderState: String, Codable, Sendable { case starting, working, waiting, finished, exited, failed, discarded }

public struct Contender: Codable, Equatable, Sendable {
    public var id: String
    public var race: String
    /// 1…N: the worktree is `<task>-<index>`.
    public var index: Int
    public var agent: AgentChoice
    public var worktree: String
    public var state: ContenderState
    public var session: SessionLink?
    public var reason: String?
    /// Its branch was deleted (orchestration.delete-race-branches). Optional,
    /// so a row from before this field still reads.
    public var branchDeleted: Bool?
}

/// The Claude session behind a contender, a dispatch or an automation's run:
/// the kit's session key, Claude's id and the transcript (plan 18).
public struct SessionLink: Codable, Equatable, Sendable {
    public var kit: String
    public var claude: String?
    public var transcript: String?
    public init(kit: String, claude: String? = nil, transcript: String? = nil) {
        self.kit = kit
        self.claude = claude
        self.transcript = transcript
    }
}

// MARK: Runs

public struct Run: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var repository: String
    /// nil: the owner coordinates; else the kit session of the agent that does.
    public var coordinator: String?
    public var caps: Caps
    public var createdAt: Date
    public var stopped = false
    /// Why it stopped: "stopped" (the owner) or "hit the cap". Optional, so
    /// a row from before this field still reads.
    public var reason: String?
}

public enum TaskState: String, Codable, Sendable { case pending, ready, dispatched, done, failed, blocked }

public enum GateState: String, Codable, Sendable { case none, waiting, approved, rejected }

public struct RunTask: Codable, Equatable, Sendable {
    public var id: String
    public var run: String
    public var title: String
    /// The text that becomes the agent's prompt.
    public var spec: String
    public var dependsOn: [String]
    public var gate: GateState
    public var state: TaskState
    /// The dispatch that spawned it (`orchestration.spawn`); nil when the
    /// owner or the coordinator added it.
    public var spawnedBy: String?
    /// 0 for a task the owner added; a spawned one is its parent's plus 1.
    public var depth: Int
    public var reason: String?
    /// The owner's dispatch waiting for a free slot (orchestration.maxAgents
    /// reached, plan 24 D1): launched as soon as one frees. Optional, so a
    /// row from before it still reads.
    public var queued: QueuedDispatch?
}

/// A dispatch the owner asked for while every slot was taken: who runs it,
/// where it starts, and (optionally) the idle terminal to reuse, by its
/// shell's pid.
public struct QueuedDispatch: Codable, Equatable, Sendable {
    public var agent: AgentChoice
    public var base: String
    public var reuseShell: Int32?
    public var at: Date
    public init(agent: AgentChoice, base: String, reuseShell: Int32? = nil, at: Date) {
        self.agent = agent
        self.base = base
        self.reuseShell = reuseShell
        self.at = at
    }
}

public enum DispatchState: String, Codable, Sendable { case starting, working, done, failed, stopped }

public struct Dispatch: Codable, Equatable, Sendable {
    public var id: String
    public var run: String
    public var task: String
    /// 1 for the first try; a retry is the next.
    public var attempt: Int
    public var agent: AgentChoice
    public var worktree: String
    public var launch: LaunchMode
    public var state: DispatchState
    public var session: SessionLink?
    public var startedAt: Date
    public var endedAt: Date?
    /// The last heartbeat, report or hook: what "stalled?" is measured from.
    public var lastSign: Date
    public var summary: String?
    public var reason: String?
    /// The session's cost as its status line last wrote it (plan 24 D1):
    /// kept here because the run's cap sums every dispatch, also those whose
    /// tab is gone. Optional, so a row from before it still reads.
    public var costUsd: Double?
}

public enum MessageKind: String, Codable, Sendable { case question, answer, message }

/// A line of a run's inbox. `from` and `to` are a dispatch id, "owner" or
/// "coordinator".
public struct RunMessage: Codable, Equatable, Sendable {
    public var id: String
    public var run: String
    public var kind: MessageKind
    public var from: String
    public var to: String
    public var text: String
    public var at: Date
    /// The question an answer answers.
    public var answers: String?
    public var read = false
}

// MARK: Automations

public enum Recurrence: Codable, Equatable, Sendable {
    /// Monday to Friday at hour:minute.
    case weekdays(hour: Int, minute: Int)
    case daily(hour: Int, minute: Int)
    case everyHours(Int)
    case once(Date)
}

public enum AutomationTarget: Codable, Equatable, Sendable {
    /// A new worktree of the repository for each run.
    case newWorktree(repository: String)
    case folder(String)
}

public enum MissedRun: String, Codable, Sendable { case runOnWake, skip }

public struct Automation: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var prompt: String
    public var recurrence: Recurrence
    public var target: AutomationTarget
    public var agent: AgentChoice
    /// Claude Code's permission mode for the run ("default", "acceptEdits"…).
    public var permissionMode: String
    public var allowedTools: [String]
    public var caps: Caps
    /// The owner's explicit choice to run on the subscription instead of the
    /// account's apiKeyHelper (ADR 0033); off for a new automation.
    public var useSubscription = false
    public var missed: MissedRun = .runOnWake
    public var enabled = false
}

public enum AutomationResult: String, Codable, Sendable { case running, done, failed, hitTheCap, stoppedWaiting, skipped }

public struct AutomationRun: Codable, Equatable, Sendable {
    public var id: String
    public var automation: String
    public var scheduledAt: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var costUsd: Double?
    public var result: AutomationResult
    public var session: SessionLink?
    public var reason: String?
}
