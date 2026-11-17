import AppKit
import Checks
import Foundation
@testable import Worktrees

// The New Task sheet (plan 29 phase B): the rules of the request, and the sheet itself.

@MainActor
func sheetButtons(_ view: NSView) -> [NSButton] { ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap(sheetButtons) }

let newTaskTests: [(name: String, body: Checks.Body)] = [
    ("the branch comes from the words, without the small ones; what is missing stops Start", {
        expect(NewTaskWords.branch(from: "Make the cache evict entries by age") == "cache-evict")
        expect(NewTaskWords.branch(from: "Corrigir o botão de pagar") == "corrigir-botao")
        var request = NewTaskRequest(prompt: "", separateCopy: false, agents: [NewTaskAgent(name: "bkdg", account: "/a")])
        expect(request.missing == nil, "no words, in the folder: the agent with no prompt")
        request.separateCopy = true
        expect(request.missing != nil, "no words and no branch: the copy has no name")
        request.prompt = "fix the login"
        expect(request.missing == nil && request.branchName == "fix-login")
        request.branch = "Login Fix!"
        expect(request.branchName == "login-fix", request.branchName)
        request.agents = []
        expect(request.missing != nil, "no agent")
    }),
    ("two agents are a race, always in copies; the button says so", {
        let one = NewTaskAgent(name: "bkdg", account: "/a", model: "opus")
        var request = NewTaskRequest(prompt: "x", separateCopy: false, agents: [one])
        expect(!request.isRace && !request.runsInCopy && NewTaskWords.startTitle(request).hasPrefix("Start task"))
        request.agents.append(NewTaskAgent(name: "pc", account: nil, machine: "pc"))
        expect(request.isRace && request.runsInCopy && NewTaskWords.startTitle(request).hasPrefix("Start race"))
        expect(one.title == "Claude Opus · bkdg" && request.agents[1].title == "Claude · pc on pc", "\(one.title) \(request.agents[1].title)")
        expect(NewTaskWords.raceNote(agents: 3, budget: 1, minutes: 20).contains("Cap US$ 1.00 · 20 min each"))
    }),
    ("the sheet: Start waits for the words and for a line that blocks; Start sends the request", { @MainActor in
        var started: [NewTaskRequest] = []
        var blocking = true
        var actions = NewTaskSheetActions()
        actions.project = "cadex"
        actions.notes = { _ in blocking ? [NewTaskNote("not trusted yet", blocks: true)] : [] }
        actions.start = { started.append($0) }
        let sheet = NewTaskSheet(request: NewTaskRequest(agents: [NewTaskAgent(name: "bkdg", account: "/a")]), actions: actions)
        // A copy with no words has no branch name yet.
        sheet.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        sheet.layoutSubtreeIfNeeded()
        let start = sheetButtons(sheet).first { $0.attributedTitle.string.hasPrefix("Start") }
        expect(start?.isEnabled == false, "no words yet")
        var request = sheet.request
        request.prompt = "fix the login"
        sheet.fill(request)
        expect(start?.isEnabled == false, "a blocking line")
        blocking = false
        sheet.refreshNotes()
        expect(start?.isEnabled == true)
        sheet.pressStart()
        expect(started.count == 1 && started[0].branchName == "fix-login")
    }),
]
