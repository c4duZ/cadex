import Checks
import Foundation
@testable import Orchestration
@testable import SessionKit

// The race's pieces (plan 24 phase C): the prompt file, Claude Code's trust,
// the board's columns, the session's cost, the refusals and the command.

let raceTests: [(name: String, body: Checks.Body)] = [
    ("the prompt file: 0600 in a 0700 folder, the text intact; empty, too big or with a NUL refused", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        let folder = dir + "/prompts"
        let text = "diga \"oi\" $(rm -rf ~) `id`; a && b\nlinha 2"
        guard case .success(let path) = PromptFiles.write(text, in: folder) else { return expect(false, "not written") }
        let mode = { (p: String) in (try? fm.attributesOfItem(atPath: p)[.posixPermissions] as? Int) ?? -1 }
        expect(mode(path) == 0o600 && mode(folder) == 0o700 && path.hasPrefix(folder + "/") && path.hasSuffix(".md"))
        expect(fm.contents(atPath: path) == Data(text.utf8))
        expect(PromptFiles.write("  \n", in: folder) == .failure(.empty))
        expect(PromptFiles.write(String(repeating: "x", count: PromptFiles.maxBytes + 1), in: folder) == .failure(.tooBig(PromptFiles.maxBytes + 1)))
        expect(PromptFiles.write("a\u{0}b", in: folder) == .failure(.notWritten))
        PromptFiles.prune(in: folder, olderThan: 60, now: Date().addingTimeInterval(120))
        expect(!fm.fileExists(atPath: path), "a day-old prompt nobody took is removed")
    }),
    ("trust: the folder, a child of a trusted one, or the worktree's repository; a sibling is not", {
        let json = Data(#"{"projects":{"/r/app":{"hasTrustDialogAccepted":true},"/r/other":{"hasTrustDialogAccepted":false},"/x":{}}}"#.utf8)
        let trusted = ClaudeTrust.trustedFolders(json)
        expect(trusted == ["/r/app"], "\(trusted)")
        expect(ClaudeTrust.isTrusted("/r/app", trusted: trusted) && ClaudeTrust.isTrusted("/r/app/src/", trusted: trusted))
        expect(ClaudeTrust.isTrusted("/r/app.worktrees/fix-1", repository: "/r/app", trusted: trusted))
        expect(!ClaudeTrust.isTrusted("/r/app.worktrees/fix-1", trusted: trusted), "a sibling folder is not a child")
        expect(!ClaudeTrust.isTrusted("/r/other", trusted: trusted) && ClaudeTrust.trustedFolders(Data("nope".utf8)).isEmpty)
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        fm.createFile(atPath: dir + "/.claude.json", contents: json)
        expect(ClaudeTrust.isTrusted("/r/app", repository: nil, configDir: dir))
        expect(!ClaudeTrust.isTrusted("/r/app", repository: nil, configDir: dir + "/none"), "no file: not trusted")
    }),
    ("refusals before anything is made: off, 1 agent, past the cap, empty or big prompt, an account without trust", {
        let agents = [AgentChoice(account: "/a/bkdg"), AgentChoice(account: nil, model: "haiku"), AgentChoice(machine: "pc")]
        var request = RaceRequest(name: "fix", prompt: "fix it", repository: "/r", base: "main", agents: agents, caps: Caps(budgetUsd: 1, maxMinutes: 5))
        expect(RaceLaunch.check(request, enabled: false, maxAgents: 6) { _ in true } == .off)
        expect(RaceLaunch.check(request, enabled: true, maxAgents: 2) { _ in true } == .tooMany(2))
        expect(RaceLaunch.check(request, enabled: true, maxAgents: 6) { _ in true } == nil)
        expect(RaceLaunch.check(request, enabled: true, maxAgents: 6) { $0 == nil } == .notTrusted(["bkdg"]), "the remote one is not read")
        request.agents = [agents[0]]
        expect(RaceLaunch.check(request, enabled: true, maxAgents: 6) { _ in true } == .tooFew)
        request.agents = agents
        request.prompt = " "
        expect(RaceLaunch.check(request, enabled: true, maxAgents: 6) { _ in true } == .emptyPrompt)
        request.prompt = String(repeating: "x", count: PromptFiles.maxBytes + 1)
        expect(RaceLaunch.check(request, enabled: true, maxAgents: 6) { _ in true } == .promptTooBig(PromptFiles.maxBytes + 1))
        expect(RaceLaunch.taskName("fix-login", index: 2) == "fix-login-2")
        expect(RaceLaunch.arguments(AgentChoice(model: "opus"), skipPermissions: true) == ["--model", "opus", "--dangerously-skip-permissions"])
    }),
    ("a contender's command: cadex claude with the prompt's file, the text never in it", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit.forTests(folder: dir + "/kit")
        kit.toolsPath = "/H/cadex"
        let prompt = "diga \"oi\" $(touch /tmp/x)"
        guard case .success(let opened) = RaceLaunch.localCommand(kit: kit, agent: AgentChoice(model: "haiku"), cwd: "/w", prompt: prompt,
                                                                   skipPermissions: false, promptFolder: dir + "/prompts")
        else { return expect(false, "refused") }
        expect(opened.command.contains("/H/cadex claude ") && opened.command.contains("--model haiku --cadex-prompt-file " + dir + "/prompts/"))
        expect(!opened.command.contains("oi") && !opened.command.contains("touch"), opened.command)
        let files = (try? fm.contentsOfDirectory(atPath: dir + "/prompts")) ?? []
        expect(files.count == 1 && fm.contents(atPath: dir + "/prompts/" + files[0]) == Data(prompt.utf8))
        kit.toolsPath = nil
        let none = RaceLaunch.localCommand(kit: kit, agent: AgentChoice(), cwd: "/w", prompt: "x", skipPermissions: false, promptFolder: dir + "/p2")
        guard case .failure(.noCadex) = none else { return expect(false, "\(none)") }
    }),
    ("the board's columns: by number, state and time, cost (— on another machine), diff, the winner and the discarded", {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let race = Race(id: "r", name: "fix", prompt: "p", repository: "/r", base: "main", caps: Caps(budgetUsd: 1, maxMinutes: 5), createdAt: t0, winner: "c1")
        let contenders = [
            Contender(id: "c2", race: "r", index: 2, agent: AgentChoice(model: "haiku", machine: "pc"), worktree: "/r.worktrees/fix-2", state: .working),
            Contender(id: "c1", race: "r", index: 1, agent: AgentChoice(account: "/a/bkdg", model: "opus"), worktree: "/r.worktrees/fix-1", state: .finished),
            Contender(id: "c3", race: "r", index: 3, agent: AgentChoice(), worktree: "/r.worktrees/fix-3", state: .discarded),
        ]
        let live: (Contender) -> ContenderLive? = { c in
            c.id == "c1" ? ContenderLive(state: .finished, since: t0, costUsd: 0.123, diff: DiffCount(files: 3, added: 40, removed: 2))
                         : ContenderLive(state: .working, since: t0.addingTimeInterval(-30), costUsd: 9)
        }
        let columns = RaceColumns.make(race: race, contenders: contenders, live: live, now: t0.addingTimeInterval(125))
        expect(columns.map(\.contender) == ["c1", "c2", "c3"])
        expect(columns[0].title == "#1 · fix-1" && columns[0].subtitle == "opus · bkdg" && columns[0].isWinner)
        expect(columns[0].elapsed == "2m 5s" && columns[0].cost == "US$ 0.12" && columns[0].diff.hasSuffix("+40 −2"), "\(columns[0])")
        expect(columns[1].cost == "—" && columns[1].subtitle == "haiku · ~/.claude · pc" && !columns[1].canCompare, "\(columns[1])")
        let capped = Contender(id: "c4", race: "r", index: 4, agent: AgentChoice(), worktree: "/w", state: .exited, reason: "hit the cap")
        expect(RaceColumns.make(race: race, contenders: [capped], live: live, now: t0)[0].state == "Stopped: hit the cap")
        expect(columns[2].isDiscarded && !columns[2].canCompare && columns[2].diff == "deleted", "\(columns[2])")
        expect(RaceColumns.costLabel(0.0048, remote: false) == "US$ 0.0048" && RaceColumns.diffLabel(DiffCount(files: 1, added: 3, removed: 0)) == "1 file +3 −0")
    }),
    ("the form: rows follow the count, accounts take turns, the model and machine chosen per row, the prompt kept", {
        let accounts = [NewRaceForm.Account(title: "bkdg", dir: "/a/bkdg"), NewRaceForm.Account(title: "default", dir: nil)]
        let form = NewRaceForm(accounts: accounts, machines: ["pc", "nas"], base: "main", maxAgents: 6)
        expect(form.contenderRows.count == 3, "three by default")
        form.choose(count: 4)
        expect(form.contenderRows.count == 4)
        form.choose(count: 2)
        expect(form.contenderRows.count == 2)
        form.nameField.stringValue = "fix-login"
        form.promptView.string = "diga \"oi\"\n$(x)"
        form.contenderRows[1].model.stringValue = "haiku"
        form.contenderRows[1].machine.selectItem(at: 2)
        let request = form.request(repository: "/r", caps: Caps(budgetUsd: 1, maxMinutes: 5))
        expect(request.name == "fix-login" && request.base == "main" && request.prompt == "diga \"oi\"\n$(x)", "\(request)")
        expect(request.agents == [AgentChoice(account: "/a/bkdg"), AgentChoice(account: nil, model: "haiku", machine: "nas")], "\(request.agents)")
        let same = [NewRaceForm.Account(title: "Org", dir: "/a/x"), NewRaceForm.Account(title: "Org", dir: "/a/y"), NewRaceForm.Account(title: "", dir: "/a/bkdg")]
        expect(NewRaceForm.titles(same) == ["Org · x", "Org · y", "bkdg"], "\(NewRaceForm.titles(same))")
        let twins = NewRaceForm(accounts: same, machines: [], base: "main", maxAgents: 6)
        expect(twins.contenderRows[0].account.numberOfItems == 3 && twins.contenderRows[0].account.titleOfSelectedItem == "Org · x")
        twins.fill(name: "n", prompt: "p", count: 2, accounts: ["/a/bkdg", "/a/y"], model: "haiku")
        expect(twins.request(repository: "/r", caps: Caps(budgetUsd: 1, maxMinutes: 1)).agents.map(\.account) == ["/a/bkdg", "/a/y"])
        let capped = NewRaceForm(accounts: [], machines: [], base: "", maxAgents: 2)
        expect(capped.contenderRows.count == 2 && capped.request(repository: "/r", caps: Caps(budgetUsd: 1, maxMinutes: 1)).agents.allSatisfy { $0.account == nil })
    }),
    ("the session's cost: cost.total_cost_usd of the status line's file; none, or a path, is nil", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        try? fm.createDirectory(atPath: dir + "/sessions", withIntermediateDirectories: true)
        fm.createFile(atPath: dir + "/sessions/abc.json", contents: Data(#"{"at":1,"cost":{"total_cost_usd":0.42,"total_duration_ms":10}}"#.utf8))
        expect(SessionCost.read(session: "abc", usage: dir) == 0.42)
        expect(SessionCost.read(session: "none", usage: dir) == nil && SessionCost.read(session: "../abc", usage: dir) == nil)
    }),
]
