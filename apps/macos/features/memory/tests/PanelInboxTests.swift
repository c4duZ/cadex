import AppKit
import Checks
import Foundation
import Strings
@testable import Memory

// The inbox and the workstreams (plan 40 F) over the recorded seed (extra/inbox in four mailboxes,
// extra/workstreams): the reading, the places and their routes, upstream's words, the writes (each a
// command's arguments and the engine's route and JSON), the screen's choices and writes with a fake
// engine, and with CADEX_SNAPSHOT_DIR memory-inbox.png, memory-inbox-empty.png and
// memory-workstreams.png, to lay over MemoryInbox.dc.html and MemoryWorkstreams.dc.html.

/// The fixtures were recorded at 13:14Z from a seed written at 21:25Z the day before.
let panelNowF = ISO8601DateFormatter().date(from: "2026-11-20T13:15:00Z")!
let siteRef = PanelProjectRef(name: "site")

@MainActor func panelInboxTests() -> [(name: String, body: Checks.Body)] { [
    ("the inbox reads the seed: cadex's mailbox first (mail waiting), the queue, the recipients, the messages", {
        guard let box = PanelMailbox.parse(panelFixture("inbox"), query: PanelMailboxQuery()) else { return expect(false) }
        expect(box.project == cadexRef && box.pendingTotal == 2 && box.pendingProjects == 1 && box.state == "pending")
        expect(box.waiting.map(\.project) == [cadexRef] && box.scopes.count == 5, "\(box.scopes.map(\.project))")
        expect(box.messages.map(\.title) == ["Site needs the engine doc", "Panel question"], "\(box.messages.map(\.title))")
        expect(box.messages[0].route == "default / site → default / cadex" && box.messages[0].agent == "Claude Code")
        expect(box.agents(in: cadexRef) == ["claude-code", "codex"] && box.agents(in: siteRef) == ["claude-code"] && box.agents(in: PanelProjectRef(name: "empty")).isEmpty)
        guard let all = PanelMailbox.parse(panelFixture("inbox-all"), query: PanelMailboxQuery(project: cadexRef, state: "")),
              let sent = PanelMailbox.parse(panelFixture("inbox-sent"), query: PanelMailboxQuery(project: cadexRef, outbox: true)),
              let empty = PanelMailbox.parse(panelFixture("inbox-empty"), query: PanelMailboxQuery(project: siteRef, state: "claimed")) else { return expect(false) }
        expect(all.messages.map(\.state) == ["pending", "pending", "claimed"] && all.state == "" && sent.state == nil, "\(all.messages.map(\.state))")
        expect(sent.messages.map(\.title) == ["Panel question"] && empty.messages.isEmpty)
        inPortuguese {
            expect(box.queueLine == "2 na fila · 1 projeto", box.queueLine)
            expect(PanelMailbox(query: PanelMailboxQuery()).queueLine == "Nenhuma mensagem aguardando agentes")
            expect(empty.emptyLine == "Nenhuma mensagem neste estado." && sent.emptyLine == "Nenhuma mensagem enviada por este projeto ainda.")
            expect(PanelMailboxQuery.states.map(PanelMailboxQuery.stateTitle) == ["Todas as mensagens", "Aguardando coleta", "Coletadas", "Canceladas", "Em edição"])
            expect(PanelMailboxQuery.chipTitle("claimed") == "coletada" && PanelMail(id: "", subject: nil, body: "", fromAgent: "", state: "").title == "Mensagem sem título")
            var held = box
            held.editing = 2
            expect(held.heldLine == "2 mensagens retidas para edição.")
        }
    }),
    ("an inbox and the workstreams are places: their routes and arguments, the sections opening them", {
        let q = PanelMailboxQuery(project: cadexRef, outbox: true, state: "", offset: 50, compose: true)
        expect(q.path == "extra/inbox?workspace=default&project=cadex&box=outbox&state=&offset=50", q.path)
        expect(q.arguments == ["section": "inbox", "scope": "default/cadex", "box": "outbox", "state": "all", "offset": "50", "compose": "1"], "\(q.arguments)")
        for place: PanelPlace in [.mailbox(q), .mailbox(PanelMailboxQuery()), .mailbox(PanelMailboxQuery(project: siteRef, state: "claimed")),
                                  .workstreams(page: 1), .workstreams(page: 3)] {
            expect(PanelPlace(arguments: place.arguments) == place, "\(place.arguments)")
        }
        expect(PanelPlace.section(.inbox).normalized == .mailbox(PanelMailboxQuery()) && PanelPlace.section(.workstreams).normalized == .workstreams(page: 1))
        expect(PanelPlace.mailbox(q).section == .inbox && PanelPlace.workstreams(page: 2).section == .workstreams && PanelPlace.mailbox(q).project == nil)
        expect(PanelLoads.paths(.workstreams(page: 2)) == ["extra/workstreams?page=2"] && PanelLoads.paths(.mailbox(PanelMailboxQuery())) == ["extra/inbox"])
        expect(MemoryPanelSection.inbox.isBuilt && MemoryPanelSection.workstreams.isBuilt )
    }),
    ("a write is a command and a POST: send, hold, save and discard, each back from its arguments", {
        let writes: [PanelWrite] = [.send(from: cadexRef, to: siteRef, agent: "claude-code", subject: "Hi", body: "Do it"),
                                           .hold(id: "m-1", mailbox: cadexRef), .save(id: "m-1", mailbox: cadexRef, subject: "", body: "New"),
                                           .discard(id: "m 2", mailbox: cadexRef)]
        for w in writes { expect(PanelWrite(command: w.command, arguments: w.arguments) == w, "\(w.arguments)") }
        expect(writes.map(\.path) == ["extra/messages", "extra/messages/m-1/edit", "extra/messages/m-1/save", "extra/messages/m%202/release"], "\(writes.map(\.path))")
        expect(writes[0].body == #"{"body":"Do it","from_project":"cadex","from_workspace":"default","subject":"Hi","to_agent":"claude-code","to_project":"site","to_workspace":"default"}"#, writes[0].body)
        expect(writes[2].body == #"{"body":"New","project":"cadex","subject":"","workspace":"default"}"#, writes[2].body)
        expect(PanelWrite(command: "memory.send-message", arguments: ["from": "cadex", "agent": "codex", "body": "x"])
               == .send(from: cadexRef, to: cadexRef, agent: "codex", subject: "", body: "x"), "the destination defaults to the source")
        expect(PanelWrite(command: "memory.save-message", arguments: ["id": "x", "mailbox": "cadex"]) == nil, "save needs the body")
    }),
    ("the screen: choices go to new places; Nova mensagem sends what was typed and says it queued; Editar opens the editor", {
        guard let box = PanelMailbox.parse(panelFixture("inbox"), query: PanelMailboxQuery()) else { return expect(false) }
        var gone: [PanelPlace] = []
        var sent: [PanelWrite] = []
        var reloads = 0
        let view = PanelInboxView(box, now: panelNowF, write: { sent.append($0) }, reload: { reloads += 1 }) { gone.append($0) }
        inPortuguese { expect(view.statePopup.said == "Aguardando coleta" || view.statePopup.said == "Awaiting collection") }
        view.boxTabs.press(1)
        expect(gone.last == .mailbox(PanelMailboxQuery(project: cadexRef, outbox: true)), "\(gone)")
        view.statePopup.pick(0)
        expect(gone.last == .mailbox(PanelMailboxQuery(project: cadexRef, state: "")), "\(gone)")
        view.projectPopup.pick(1)
        expect(gone.last == .mailbox(PanelMailboxQuery(project: siteRef)), "\(gone)")
        let compose = view.compose!
        expect(!compose.queueButton.isEnabled, "no agent chosen yet")
        compose.agentPopup.pick(1)
        compose.type(subject: "Panel", body: "Please check")
        expect(compose.queueButton.isEnabled)
        compose.toPopup.pick(1)
        expect(compose.agent == nil && !compose.queueButton.isEnabled, "codex has no session in site")
        compose.agentPopup.pick(0)
        compose.queueButton.performClick(nil)
        expect(sent == [.send(from: cadexRef, to: siteRef, agent: "claude-code", subject: "Panel", body: "Please check")], "\(sent)")
        view.finished(sent[0], .success(Data(#"{"message_id":"x","state":"pending"}"#.utf8)))
        expect(compose.resultSaid.contains("Claude Code") && compose.bodyView.string.isEmpty, compose.resultSaid)
        view.finished(sent[0], .failure(PanelReadError(words: "This inbox is full.")))
        expect(compose.resultSaid == "This inbox is full.", compose.resultSaid)
        let row = view.rows[0]
        row.toggle()
        row.press("edit")
        expect(sent.last == .hold(id: row.message.id, mailbox: cadexRef), "\(String(describing: sent.last))")
        view.finished(sent.last!, .success(Data(#"{"message_id":"x","state":"editing","subject":"S","body":"B"}"#.utf8)))
        expect(row.editing && row.subjectField.stringValue == "S" && row.bodyView.string == "B")
        row.bodyView.string = "Better"
        row.press("save")
        expect(sent.last == .save(id: row.message.id, mailbox: cadexRef, subject: "S", body: "Better"))
        view.finished(sent.last!, .success(Data("{}".utf8)))
        expect(reloads == 1)
        view.finished(.discard(id: row.message.id, mailbox: cadexRef), .failure(PanelReadError(words: "This message is no longer being edited.")))
        expect(reloads == 1)
    }),
    ("the page performs a write itself without the app, and the answer reaches the inbox on screen", {
        var actions = MemoryPanelActions()
        actions.read = { path, done in done(panelAnswer(path).map { .success($0) } ?? .failure(PanelReadError(words: path))) }
        var posted: [(String, String)] = []
        actions.write = { path, body, done in posted.append((path, body)); done(.failure(PanelReadError(words: "refused"))) }
        let page = MemoryPanelDocument(actions: actions)
        page.go(.mailbox(PanelMailboxQuery()))
        guard let inbox = page.screen as? PanelInboxView else { return expect(false, "\(String(describing: page.screen))") }
        expect(page.showsInbox && inbox.rows.count == 2)
        inbox.rows[1].toggle()
        inbox.rows[1].press("edit")
        expect(posted.map(\.0) == ["extra/messages/\(inbox.rows[1].message.id)/edit"], "\(posted)")
        page.go(.workstreams(page: 1))
        expect(page.screen is PanelWorkstreamsView && page.place.section == .workstreams)
    }),
    ("the workstreams read the seed: one, completed, its run and harness; the sent mailbox shows no Editar", {
        guard let w = PanelWorkstreams.parse(panelFixture("workstreams")) else { return expect(false) }
        expect(w.page == 1 && !w.hasNext && w.rows.count == 1)
        let row = w.rows[0]
        expect(row.name == "panel rewrite" && row.project == cadexRef && row.status == "completed" && row.latestAgent == "claude-code" && row.events == 1)
        expect(row.harnesses == ["claude-code"] && row.ended != nil)
        inPortuguese { expect(row.statusTitle == "concluído") }
        var gone: [PanelPlace] = []
        let view = PanelWorkstreamsView(w, now: panelNowF) { gone.append($0) }
        expect(view.table.rows.count == 1)
        guard let sent = PanelMailbox.parse(panelFixture("inbox-sent"), query: PanelMailboxQuery(project: cadexRef, outbox: true)) else { return expect(false) }
        let outbox = PanelInboxView(sent, now: panelNowF, write: { _ in }, reload: {}) { _ in }
        outbox.rows[0].toggle()
        outbox.rows[0].press("edit")
        expect(outbox.rows[0].buttons.isEmpty, "Enviadas cannot edit")
    }),
    ("snapshots: the inbox, an empty mailbox and the workstreams", {
        inPortuguese {
            guard let box = PanelMailbox.parse(panelFixture("inbox"), query: PanelMailboxQuery()),
                  let empty = PanelMailbox.parse(panelFixture("inbox-empty"), query: PanelMailboxQuery(project: siteRef, state: "claimed")),
                  let w = PanelWorkstreams.parse(panelFixture("workstreams")) else { return expect(false) }
            let inbox = PanelInboxView(box, now: panelNowF, write: { _ in }, reload: {}) { _ in }
            inbox.rows[1].toggle()
            panelSnapshot(inbox, "memory-inbox.png")
            panelSnapshot(PanelInboxView(empty, now: panelNowF, write: { _ in }, reload: {}) { _ in }, "memory-inbox-empty.png")
            panelSnapshot(PanelWorkstreamsView(w, now: panelNowF) { _ in }, "memory-workstreams.png")
        }
    }),
] }
