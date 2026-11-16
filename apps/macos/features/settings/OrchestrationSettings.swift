import Foundation

extension Settings {
    /// Many agents at once (docs/spec/orchestration.md, plan 24): races and
    /// runs, and scheduled automations, each off until the owner turns it on
    /// (docs/adr/0033-cadex-launches-agents.md).
    public struct Orchestration: Equatable, Sendable {
        /// Races and runs. Off: no agent opened with a prompt, no state opened.
        public var enabled = false
        /// Scheduled automations. Off: no LaunchAgent and none run.
        public var automations = false
        /// Agents alive at once across races, runs and automations.
        public var maxAgents = 6
        /// How deep spawned tasks may go (a spawned task's own spawn is 2).
        public var maxDepth = 2
        /// Minutes without a sign of life before a dispatch shows "stalled?".
        public var heartbeatMinutes = 10
        /// The Mac stays awake while an automation runs (the power feature).
        public var keepAwakeDuringRuns = true
        /// The caps a new race, run or automation proposes.
        public var defaultBudgetUsd = 5.0
        public var defaultMaxMinutes = 60
    }
}
