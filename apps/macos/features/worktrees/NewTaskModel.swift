import Foundation
import Strings

/// What the New Task sheet asks (docs/spec/worktrees.md; the NewTask mockup): the owner's words,
/// where it runs and who does it. One agent is a task, two or more a race (each in its own copy).
/// Pure, so the rules are testable; the sheet draws it and the app makes it.
public struct NewTaskRequest: Equatable, Sendable {
    public var prompt: String
    /// A separate copy on `branch` (a worktree); false: the project's folder itself.
    public var separateCopy: Bool
    public var branch: String
    public var agents: [NewTaskAgent]

    public init(prompt: String = "", separateCopy: Bool = true, branch: String = "", agents: [NewTaskAgent] = []) {
        self.prompt = prompt
        self.separateCopy = separateCopy
        self.branch = branch
        self.agents = agents
    }

    public var isRace: Bool { agents.count > 1 }

    /// A race always runs in copies: each agent gets its own.
    public var runsInCopy: Bool { separateCopy || isRace }

    /// The branch typed, else the one the words suggest.
    public var branchName: String {
        // What the owner typed is kept, every word ("orchestration-e" lost its "e", 2026-11-17).
        let typed = NewTaskWords.slug(branch)
        return typed.isEmpty ? NewTaskWords.branch(from: prompt) : typed
    }

    /// Why Start cannot run yet; nil when it can.
    /// Empty words open the agent with no prompt (the spec); a race needs them, all its agents
    /// get the same.
    public var missing: String? {
        if agents.isEmpty { return T("Add an agent", "Adicione um agente") }
        if isRace, prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return T("Write what the agents should do", "Escreva o que os agentes devem fazer") }
        if runsInCopy, branchName.isEmpty { return T("Name the branch", "Dê um nome ao branch") }
        return nil
    }
}

/// One agent of the sheet: an account of Claude Code, here or on another machine, with a model.
public struct NewTaskAgent: Equatable, Sendable {
    /// The account's name ("bkdg"), or the machine's for one that runs there with its own login.
    public var name: String
    /// The account's folder; nil for the default one.
    public var account: String?
    /// Another machine's name ("Run on"); empty for this Mac.
    public var machine: String
    /// "84% used", from the usage the status line kept; empty when unknown.
    public var usage: String
    /// "opus", "haiku"; empty for the account's own default.
    public var model: String
    /// Codex instead of Claude Code (its CODEX_HOME in `account`).
    public var isCodex: Bool

    public init(name: String, account: String?, machine: String = "", usage: String = "", model: String = "", isCodex: Bool = false) {
        self.name = name
        self.account = account
        self.machine = machine
        self.usage = usage
        self.model = model
        self.isCodex = isCodex
    }

    /// "Claude Opus · bkdg", "Codex · pro", "Claude · ubuntu-dev" (the mockup's rows).
    public var title: String {
        (isCodex ? "Codex" : "Claude") + (model.isEmpty ? "" : " " + model.prefix(1).uppercased() + model.dropFirst()) + " · " + name
            + (machine.isEmpty ? "" : T(" on \(machine)", " em \(machine)"))
    }

    /// The models the row's menu offers (Claude's; Codex keeps its own default).
    public static let models = ["", "opus", "sonnet", "haiku"]
}

public enum NewTaskWords {
    /// A branch from words: lowercase, letters and digits joined by "-", the first few words
    /// without the small ones ("Make the cache evict entries by age" is "cache-evict", the mockup's).
    public static func branch(from text: String, words limit: Int = 2) -> String {
        let small: Set<String> = ["a", "an", "the", "to", "of", "in", "on", "and", "or", "for", "by", "with", "make", "do", "please",
                                  "o", "os", "as", "um", "uma", "de", "da", "do", "das", "dos", "e", "em", "no", "na", "para", "por", "com", "faz", "faça"]
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let words = folded.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        let kept = words.filter { !small.contains($0) && $0.allSatisfy { $0.isASCII } }
        return kept.prefix(limit).joined(separator: "-")
    }

    /// A typed branch made safe: lowercase, letters and digits joined by "-", nothing dropped.
    public static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return folded.split { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") || !$0.isASCII }.joined(separator: "-")
    }

    /// The race's note: "With 3 agents this is a race: …".
    public static func raceNote(agents: Int, budget: Double, minutes: Int) -> String {
        T("⚑ With \(agents) agents this is a race: each gets its own copy, you compare and keep one. Cap US$ \(String(format: "%.2f", budget)) · \(minutes) min each.",
          "⚑ Com \(agents) agentes é uma corrida: cada um ganha sua cópia, você compara e fica com uma. Teto de US$ \(String(format: "%.2f", budget)) · \(minutes) min cada.")
    }

    /// "Start task ⌘↩" or "Start race ⌘↩".
    public static func startTitle(_ request: NewTaskRequest) -> String {
        request.isRace ? T("Start race  ⌘↩", "Começar corrida  ⌘↩") : T("Start task  ⌘↩", "Começar tarefa  ⌘↩")
    }
}
