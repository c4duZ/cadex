import AppKit
import Checks
import Foundation
import UILooks
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
        expect(cards.contains { $0.kind == .question && $0.title == "Azul ou verde?" && $0.options == ["Azul", "Verde"] }, "the options apart (plan 26 D2)")
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
    ("the feed narrows to a kind and a project; the bell's page reads only while it shows", {
        let attention = AgentAttention.shared
        attention.update([report("f1", pid: 41, .working)])
        attention.update([report("f1", pid: 41, .done)])
        attention.note(.taskCreated, text: "new task", project: "other")
        expect(attention.feed(kind: .finished, project: nil).allSatisfy { $0.kind == .finished } && !attention.feed(kind: .finished, project: nil).isEmpty)
        expect(attention.feed(kind: nil, project: "other").map(\.text) == ["new task"])
        expect(attention.feedProjects.contains("cadex") && attention.feedProjects.contains("other"))
        let page = AgentAttentionView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        page.isHidden = true
        let window = NSWindow(contentRect: page.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(page)
        expect(!page.isWatching, "hidden: no watch")
        page.isHidden = false
        expect(page.isWatching, "shown: it watches")
        page.removeFromSuperview()
        expect(!page.isWatching)
    }),
    ("a card says what the agent waits for, with a heading, even when the agent sent no text (plan 24 F)", {
        let attention = AgentAttention.shared
        attention.isEnabled = true
        attention.update([report("c1", pid: 61, .working)])
        attention.update([report("c1", pid: 61, .blocked, .permission, "")])
        let page = AgentAttentionView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let window = NSWindow(contentRect: page.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(page)
        page.render()
        page.layoutSubtreeIfNeeded()
        func texts(_ view: NSView) -> [NSTextField] { (view as? NSTextField).map { [$0] } ?? [] + view.subviews.flatMap(texts) }
        let heading = texts(page).first { $0.stringValue == "Waiting for a permission" }
        expect(heading != nil, "\(texts(page).map(\.stringValue))")
        expect((heading?.frame.height ?? 0) > 0, "the heading has a height: \(heading?.frame ?? .zero)")
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let bitmap = page.bitmapImageRepForCachingDisplay(in: page.bounds) {
            page.cacheDisplay(in: page.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/attention-card.png"))
        }
        page.removeFromSuperview()
        attention.update([])
    }),
    ("the bell's popover: a permission with Allow and Deny, a question, what finished (CADEX_SNAPSHOT_DIR: bell-popover.png)", {
        let attention = AgentAttention.shared
        attention.isEnabled = true
        attention.update([report("p1", pid: 71, .working), report("q1", pid: 72, .working), report("d1", pid: 73, .working)])
        attention.update([report("p1", pid: 71, .blocked, .permission, "approve Bash: make perf"),
                          report("q1", pid: 72, .blocked, .question, "answer: Which checkout copy? (Keep the old · Use the new)"),
                          report("d1", pid: 73, .done)])
        let id = attention.addPermission(pid: 71, tool: "Bash", subject: "make perf", project: "cadex", session: "perf-subagent-window",
                                         account: "bhband", key: "p1") { _ in }
        let page = AgentAttentionView(frame: .zero)
        let width = DesignTokens.Popover.bellWidth
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: window.contentLayoutRect)
        root.wantsLayer = true
        root.layer?.backgroundColor = DesignTokens.Popover.bg.cgColor
        window.contentView = root
        page.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(page)
        NSLayoutConstraint.activate([page.topAnchor.constraint(equalTo: root.topAnchor), page.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                                     page.widthAnchor.constraint(equalToConstant: width)])
        page.render()
        root.layoutSubtreeIfNeeded()
        func texts(_ view: NSView) -> [String] { ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(texts) }
        func buttons(_ view: NSView) -> [String] { ((view as? NSButton).map { [$0.attributedTitle.string] } ?? []) + view.subviews.flatMap(buttons) }
        expect(texts(page).contains("Wants to run Bash") && texts(page).contains("Asks a question"), "\(texts(page))")
        expect(texts(page).contains("Which checkout copy?") && buttons(page).contains("Use the new"), "the question's options as buttons: \(buttons(page))")
        expect(buttons(page).contains("Allow") && buttons(page).contains("Deny") && buttons(page).contains("Go to tab"), "\(buttons(page))")
        expect(texts(page).contains("EARLIER"), "what finished, under EARLIER")
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/bell-popover.png"))
        }
        attention.resolve(id)
        attention.update([])
    }),
    ("an answer's keys: an option's number at once; the words after the type-something number and Return (tested 2026-11-17)", {
        let parsed = AgentAnswer.parse("Which color? (Red · Blue)")
        expect(parsed.question == "Which color?" && parsed.options == ["Red", "Blue"], "\(parsed)")
        expect(AgentAnswer.parse("Done? Yes").options.isEmpty && AgentAnswer.parse("(only one)").options.isEmpty)
        expect(AgentAnswer.keys(.option(1), options: 2) == ["2"])
        expect(AgentAnswer.keys(.text("Green\nnow"), options: 2) == ["3", "Green now", "\r"], "one line")
        expect(AgentAnswer.keys(.option(2), options: 2) == nil && AgentAnswer.keys(.text("  "), options: 2) == nil)
        expect(AgentAnswer.keys(.option(0), options: 0) == nil, "no options known: nothing to type")
    }),
    ("an answer to a question the agent left types nothing and the feed says so", {
        let attention = AgentAttention.shared
        attention.isEnabled = true
        attention.update([report("q9", pid: 79, .working)])
        attention.update([report("q9", pid: 79, .blocked, .question, "answer: Which? (A · B)")])
        var sent: [AgentAnswer.Reply] = []
        attention.onAnswer = { _, reply in sent.append(reply); return false }
        let card = attention.cards.first { $0.kind == .question }
        let id = card?.id ?? "", asked = card?.message ?? ""
        attention.answerQuestion(id, asked: asked, .option(1))
        expect(sent == [.option(1)], "\(sent)")
        expect(attention.feed.first?.kind == .note && attention.feed.first?.text.hasPrefix("The agent moved on") == true, "\(attention.feed.first.map(\.text) ?? "")")
        // A newer question in the same tab keeps the card's id: the old answer must not reach it.
        attention.update([report("q9", pid: 79, .blocked, .question, "answer: Other? (C · D)")])
        attention.onAnswer = { _, reply in sent.append(reply); return true }
        attention.answerQuestion(id, asked: asked, .option(0))
        expect(sent.count == 1, "an answer to the old question reached the new one")
        // Answered: the card goes, a second click sends nothing; a new report brings it back.
        let next = attention.cards.first { $0.kind == .question }?.message ?? ""
        attention.answerQuestion(id, asked: next, .option(0))
        expect(sent.count == 2 && !attention.cards.contains { $0.id == id }, "answered card stays")
        attention.answerQuestion(id, asked: next, .option(0))
        expect(sent.count == 2, "a second click typed again")
        attention.update([report("q9", pid: 79, .blocked, .question, "answer: Third? (E · F)")])
        expect(attention.cards.contains { $0.id == id }, "the next question shows")
        attention.onAnswer = nil
        attention.update([])
    }),
    ("a permission reported by the agent and then by its hook is one line in the feed", {
        let attention = AgentAttention()
        attention.update([report("t9", pid: 90, .working)])
        attention.update([report("t9", pid: 90, .blocked, .permission, "approve Bash: rm x")])
        _ = attention.addPermission(pid: 90, tool: "Bash", subject: "rm x", project: "cadex", session: "s", account: "a", key: "t9") { _ in }
        expect(attention.feed.filter { $0.kind == .permission }.count == 1, "\(attention.feed.map(\.text))")
    }),
]
