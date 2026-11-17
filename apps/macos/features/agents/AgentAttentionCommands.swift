import CommandPalette
import Foundation
import Icons
import Strings

/// The attention's commands (ADR 0005; docs/spec/agents.md, Quadro): Allow
/// and Deny list the requests whose hook waits, Answer lists the options of the open questions,
/// Mark as Unread lists the feed's lines. Each acts only on the one the owner picks.
public enum AgentAttentionCommands {
    @MainActor
    public static func commands(palette: CommandPaletteController) -> [Command] {
        let attention = AgentAttention.shared
        func requests(_ placeholder: String, _ act: @escaping @MainActor (String) -> Void) -> Command.Action {
            .run {
                palette.open(AgentChoiceSource(placeholder: placeholder, empty: T("No request waits for an answer", "Nenhum pedido espera resposta"), items: {
                    attention.cards.filter(\.canAnswer).map { card in
                        PaletteItem(id: card.id, title: card.title + (card.detail.isEmpty ? "" : ": " + card.detail),
                                    detail: [card.project, card.session].filter { !$0.isEmpty }.joined(separator: " · "), icon: .lockKey)
                    }
                }, choose: act))
            }
        }
        return [
            Command(id: "agents.approve", title: T("Allow an Agent's Request…", "Permitir o pedido de um agente…"),
                    keywords: ["allow", "approve", "permission", "permitir", "aprovar", "permissão"], category: .terminal,
                    action: requests(T("The request to allow", "O pedido a permitir")) { attention.approve($0) }),
            Command(id: "agents.deny", title: T("Deny an Agent's Request…", "Negar o pedido de um agente…"),
                    keywords: ["deny", "refuse", "permission", "negar", "recusar", "permissão"], category: .terminal,
                    action: requests(T("The request to deny", "O pedido a negar")) { attention.deny($0) }),
            // An option of an open question, typed in its agent's terminal (ADR 0036); the
            // words of one's own go from the bell's field.
            Command(id: "agents.answer", title: T("Answer an Agent's Question…", "Responder a pergunta de um agente…"),
                    keywords: ["answer", "question", "option", "responder", "pergunta", "opção"], category: .terminal,
                    action: .run {
                        palette.open(AgentChoiceSource(placeholder: T("The answer", "A resposta"), empty: T("No question with options waits", "Nenhuma pergunta com opções espera"), items: {
                            attention.cards.filter { $0.kind == .question }.flatMap { card in
                                card.options.enumerated().map { index, option in
                                    PaletteItem(id: card.id + "\u{1}" + String(index) + "\u{1}" + card.message, title: card.title + " → " + option,
                                                detail: [card.project, card.session].filter { !$0.isEmpty }.joined(separator: " · "), icon: .question)
                                }
                            }
                        }, choose: { picked in
                            // The question as listed travels with the pick: a newer one in the same
                            // tab must not take this answer.
                            let parts = picked.components(separatedBy: "\u{1}")
                            guard parts.count >= 3, let index = Int(parts[1]) else { return }
                            attention.answerQuestion(parts[0], asked: parts[2...].joined(separator: "\u{1}"), .option(index))
                        }))
                    }),
            Command(id: "agents.mark-unread", title: T("Mark an Agent as Unread…", "Marcar um agente como não lido…"),
                    keywords: ["unread", "attention", "feed", "não lido", "atenção"], category: .terminal,
                    action: .run {
                        palette.open(AgentChoiceSource(placeholder: T("The agent to mark", "O agente a marcar"), empty: T("Nothing in the feed", "Nada no feed"), items: {
                            var seen: Set<String> = []
                            return attention.feed.compactMap { entry -> PaletteItem? in
                                guard let key = entry.key, seen.insert(key).inserted else { return nil }
                                return PaletteItem(id: key, title: entry.session.isEmpty ? entry.project : entry.session,
                                                   detail: [entry.project, entry.account].filter { !$0.isEmpty }.joined(separator: " · "), icon: .eye)
                            }
                        }, choose: { attention.markUnread($0) }))
                    }),
        ]
    }
}
