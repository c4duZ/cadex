import Foundation
import Strings

/// Why an automation's run does not start (plan 24 E): said in its history
/// as a failed run, and to the owner when they asked ("Run Now").
public enum AutomationRefusal: Error, Equatable {
    case off
    case emptyPrompt
    case promptTooBig(Int)
    case noFolder(String)
    case notTrusted(String)
    /// Not on the subscription and the account has no apiKeyHelper.
    case noApiKey(String)

    public var message: String {
        switch self {
        case .off: return T("Automations are off in Settings › Many Agents.", "Automações estão desligadas em Configurações › Muitos agentes.")
        case .emptyPrompt: return RaceRefusal.emptyPrompt.message
        case .promptTooBig(let bytes): return RaceRefusal.promptTooBig(bytes).message
        case .noFolder(let path): return T("The folder \(path) is gone.", "A pasta \(path) sumiu.")
        case .notTrusted(let account): return DispatchRefusal.notTrusted(account, dir: nil).message
        case .noApiKey(let account):
            return T("\(account) has no apiKeyHelper in its settings.json: give it one, or choose \"Use the subscription\" for this automation.",
                     "\(account) não tem apiKeyHelper no settings.json: dê um a ela, ou escolha \"Usar a assinatura\" nesta automação.")
        }
    }
}

public enum AutomationLaunch {
    /// The checks before a run: on, a prompt that fits, the folder there
    /// (a fixed one; a new worktree's repository), Claude Code's trust, and
    /// the API key unless the owner chose the subscription (ADR 0033).
    public static func check(_ automation: Automation, enabled: Bool, folderExists: (String) -> Bool, trusts: (String, String?) -> Bool,
                             hasApiKeyHelper: (String?) -> Bool) -> AutomationRefusal? {
        guard enabled else { return .off }
        guard !automation.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .emptyPrompt }
        let bytes = Data(automation.prompt.utf8).count
        guard bytes <= PromptFiles.maxBytes else { return .promptTooBig(bytes) }
        let folder = place(automation)
        guard folderExists(folder) else { return .noFolder(folder) }
        let account = automation.agent.account.map { ($0 as NSString).lastPathComponent } ?? "~/.claude"
        guard trusts(folder, automation.agent.account) else { return .notTrusted(account) }
        guard automation.useSubscription || hasApiKeyHelper(automation.agent.account) else { return .noApiKey(account) }
        return nil
    }

    /// The repository (a new worktree each run) or the fixed folder.
    public static func place(_ automation: Automation) -> String {
        switch automation.target {
        case .newWorktree(let repository): return repository
        case .folder(let folder): return folder
        }
    }

    /// The words after `claude`: the model, the permission mode and the
    /// allowed tools, each option one word (`--allowedTools` takes several
    /// values and would swallow the prompt, which comes last).
    public static func arguments(_ automation: Automation) -> [String] {
        var words = automation.agent.model.isEmpty ? [] : ["--model", automation.agent.model]
        // Always said, "default" too: left out, the account's own default mode
        // (Claude Code's auto mode) ran a Bash command no one approved (2026-11-16).
        words.append("--permission-mode=" + (automation.permissionMode.isEmpty ? "default" : automation.permissionMode))
        let tools = automation.allowedTools.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !tools.isEmpty { words.append("--allowedTools=" + tools.joined(separator: ",")) }
        return words
    }

    /// Whether an account's settings.json names an apiKeyHelper (read, never
    /// written; the key itself is Claude Code's, ADR 0033). `home` for tests.
    public static func hasApiKeyHelper(configDir: String?, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> Bool {
        let file = (configDir ?? home + "/.claude") + "/settings.json"
        guard let data = FileManager.default.contents(atPath: file),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let helper = root["apiKeyHelper"] as? String else { return false }
        return !helper.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The task name of a run's new worktree: `<automation>-<yyyyMMdd-HHmm>`.
    public static func taskName(_ automation: Automation, at date: Date) -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyyMMdd-HHmm"
        format.locale = Locale(identifier: "en_US_POSIX")
        return String(automation.name.prefix(40)) + "-" + format.string(from: date)
    }
}

extension AutomationBook {
    public func automation(_ id: String) throws -> Automation? { try store.get(.automations, id: id) }

    /// The time of its newest run (skipped ones too): what "due" counts from.
    public func lastScheduled(_ automation: String) throws -> Date? { try history(of: automation).first?.scheduledAt }

    /// Turns it on or off; on, from now (a time it was off is not missed).
    public func turn(_ id: String, on: Bool, now: Date = Date()) throws {
        guard var automation = try automation(id) else { throw RunError.unknown(id) }
        automation.enabled = on
        if on { automation.enabledAt = now }
        try save(automation)
    }

    /// A run that starts now, for the time it was due.
    public func start(_ automation: Automation, scheduledAt: Date, now: Date = Date()) throws -> AutomationRun {
        let run = AutomationRun(id: newId(), automation: automation.id, scheduledAt: scheduledAt, startedAt: now, result: .running)
        try record(run)
        return run
    }

    /// A skipped (or refused) time, recorded so it is not due again.
    public func skip(_ automation: String, at: Date, result: AutomationResult = .skipped, reason: String, now: Date = Date()) throws {
        try record(AutomationRun(id: newId(), automation: automation, scheduledAt: at, startedAt: result == .skipped ? nil : now,
                                 endedAt: now, result: result, reason: reason))
    }

    /// Ends a running run with its result.
    public func finish(_ id: String, automation: String, result: AutomationResult, cost: Double?, reason: String? = nil, now: Date = Date()) throws {
        guard var run = try history(of: automation).first(where: { $0.id == id }), run.result == .running else { return }
        run.result = result
        run.endedAt = now
        run.costUsd = cost ?? run.costUsd
        run.reason = reason
        try record(run)
    }

    /// The runs still going, of every automation.
    public func runningRuns() throws -> [AutomationRun] {
        try (store.all(.automationRuns) as [AutomationRun]).filter { $0.result == .running }
    }
}
