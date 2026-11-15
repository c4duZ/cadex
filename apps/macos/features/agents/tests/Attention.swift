import Checks
import Foundation
@testable import Agents

// Attention in one place (plan 19 phase C; docs/spec/agents.md, Atenção and
// Quadro): the board's cards, the feed and the unseen count.

func report(_ key: String, pid: Int32, _ state: AgentReport.State, _ kind: AgentReport.Kind = .none, _ message: String = "",
            unseen: Bool = false) -> AgentReport {
    AgentReport(key: key, pid: pid, state: state, kind: kind, message: message, finishedUnseen: unseen,
                project: "cadex", session: "Fix login", account: "bhband")
}

let attentionChecks: [(name: String, body: Checks.Body)] = [
    ("a waiting hook is a card with Allow and Deny; each click answers it once, in Claude Code's format", {
        let attention = AgentAttention()
        var replies: [String?] = []
        let id = attention.addPermission(pid: 7, tool: "Bash", subject: "rm x", project: "cadex", session: "s", account: "a", key: "t1") { replies.append($0) }
        expect(attention.cards.count == 1 && attention.cards[0].canAnswer && attention.cards[0].detail == "rm x" && attention.unseen == 1)
        attention.approve(id)
        attention.approve(id)
        expect(replies.count == 1 && attention.cards.isEmpty, "one answer, then the card goes")
        let allow = (try? JSONSerialization.jsonObject(with: Data((replies[0] ?? "").utf8))) as? [String: Any]
        let decision = (allow?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        expect(decision?["behavior"] as? String == "allow", "\(String(describing: replies[0]))")
        let other = attention.addPermission(pid: 8, tool: "Edit", subject: "a.swift", project: "p", session: "s", account: "a", key: nil) { replies.append($0) }
        attention.deny(other)
        expect(replies.last??.contains("\"deny\"") == true && replies.last??.contains("The owner denied this in Cadex.") == true)
        expect(attention.feed.filter { $0.kind == .permission }.count == 2)
    }),
    ("an agent blocked without a waiting hook is a card to go to; with one, a single card", {
        let attention = AgentAttention()
        attention.update([report("t1", pid: 7, .blocked, .question, "answer: Azul ou verde? (Azul · Verde)"),
                          report("t2", pid: 9, .blocked, .permission, "approve Bash: ls")])
        let cards = attention.cards
        expect(cards.count == 2 && cards.allSatisfy { !$0.canAnswer }, "\(cards)")
        expect(cards.contains { $0.kind == .question && $0.title == "Azul ou verde? (Azul · Verde)" })
        expect(cards.contains { $0.kind == .permission && $0.title == "Bash" && $0.detail == "ls" })
        _ = attention.addPermission(pid: 9, tool: "Bash", subject: "ls", project: "p", session: "s", account: "a", key: "t2") { _ in }
        expect(attention.cards.count == 2 && attention.cards.contains { $0.pid == 9 && $0.canAnswer }, "the hook's card stands for both")
    }),
    ("answered in the TUI: the agent leaves blocked and its card goes, the hook unanswered; not before it was blocked", {
        let attention = AgentAttention()
        var replies: [String?] = []
        attention.update([report("t1", pid: 7, .working)])
        _ = attention.addPermission(pid: 7, tool: "Bash", subject: "rm x", project: "p", session: "s", account: "a", key: "t1") { replies.append($0) }
        attention.update([report("t1", pid: 7, .working, .none, "still")])
        expect(attention.cards.count == 1 && replies.isEmpty, "the hook can come before the blocked report")
        attention.update([report("t1", pid: 7, .blocked, .permission, "approve Bash: rm x")])
        attention.update([report("t1", pid: 7, .working)])
        expect(attention.cards.isEmpty && replies.count == 1 && replies[0] == nil, "\(replies)")
    }),
    ("the feed: finished, questions and failures as they happen, newest first, at most 200; the count adds the unseen", {
        let attention = AgentAttention()
        attention.update([report("t1", pid: 1, .working)])
        attention.update([report("t1", pid: 1, .done, .none, "", unseen: true)])
        attention.update([report("t1", pid: 1, .done, .none, "", unseen: true)])
        expect(attention.feed.map(\.kind) == [.finished], "\(attention.feed.map(\.kind))")
        expect(attention.unseen == 1, "a finished agent nobody saw counts")
        attention.update([report("t1", pid: 1, .blocked, .question, "answer: Qual?")])
        expect(attention.feed.first?.kind == .question && attention.feed.first?.text == "Qual?")
        for i in 0..<250 { attention.note(.taskCreated, text: "t\(i)", project: "p") }
        expect(attention.feed.count == 200 && attention.feed.first?.text == "t249")
        attention.isEnabled = false
        expect(attention.unseen == 0 && attention.cards.isEmpty, "agents.attention off")
    }),
]
