import AppKit
import Agents
import CommandPalette
import Sidebar
import Strings

/// The needs-you queue of ADR 0039 (plan 38 phase C): the open requests (the bell's, which left the
/// top bar) on top of the sidebar, in every view; with the sidebar closed, a pill in the top bar
/// says who waits. A click goes to that agent's terminal, where Claude's own dialog is.
extension WindowSession {
    /// The open requests as the queue draws them, oldest first.
    static func queueRequests() -> [WorkRequest] {
        AgentAttention.shared.cards.sorted { $0.at < $1.at }.map { card in
            WorkRequest(id: card.id, who: card.session.isEmpty ? card.project : card.session, project: card.project,
                        ask: askWords(card), since: card.at)
        }
    }

    /// What a request asks, in a sentence: "wants to run npm install stripe", "wants to use Edit:
    /// App.swift", or the question itself.
    static func askWords(_ card: AgentRequest) -> String {
        switch card.kind {
        case .question: return card.title
        case .permission:
            if card.title == "Bash" { return T("wants to run ", "quer rodar ") + card.detail }
            return T("wants to use \(card.title)", "quer usar \(card.title)") + (card.detail.isEmpty ? "" : ": " + card.detail)
        }
    }

    /// The queue and the pill, from the open requests.
    func drawQueue() {
        guard let workspace else { return }
        let requests = Self.queueRequests()
        workspace.sidebar.showQueue(requests)
        let first = requests.first.map { $0.who + T(" needs you", " precisa de você") }
        let pill = requests.count > 1 ? T("\(requests.count) need you", "\(requests.count) precisam de você") : first
        // The narrow strip has its own box; the pill is for the sidebar closed in a wide window.
        workspace.rail.requests = requests.count
        workspace.titleBar.setNeeds(workspace.inspectorVisible || workspace.isNarrow ? nil : pill)
    }

    /// A request of the queue clicked: its agent's terminal, wherever it is.
    func goToRequest(_ id: String) {
        guard let card = AgentAttention.shared.cards.first(where: { $0.id == id }) else { return NSSound.beep() }
        app.goToAgent(key: card.key, pid: card.pid)
    }

    func needsQueueCommands() -> [Command] {
        [Command(id: "agents.go-to-request", title: T("Go to the Agent That Waits for You", "Ir ao agente que espera você"),
                 keywords: ["needs you", "request", "permission", "waiting", "precisa", "pedido", "permissão", "esperando"],
                 category: .terminal,
                 action: .run { [weak self] in
                     // One: straight to it; more: the list of them.
                     let requests = Self.queueRequests()
                     if requests.count == 1 { self?.goToRequest(requests[0].id) } else { _ = self?.commands.run("agents.show-attention") }
                 },
                 unavailableReason: { AgentAttention.shared.cards.isEmpty ? T("Nothing waits for you", "Nada espera você") : nil })]
    }
}
