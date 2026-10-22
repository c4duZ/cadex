import Strings

/// A notification's words (docs/spec/agents.md, Notificações), as the
/// terminals and agent tools write theirs: the kind in the title, first
/// read, with the agent's name; where it is in the subtitle; the detail in
/// the body. No picture: macOS shows the app's icon on the left and lets no
/// app change it, and the picture on the right looked out of place (the
/// owner, 2026-10-22; research in docs/spec/agents.md).
public struct AgentNotifyText: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let body: String

    /// Which of the three sounds plays (agents.soundPermission, -Question, -Finished).
    public enum Kind: String, Sendable { case permission, question, finished }

    public static func kind(of stop: AgentStop) -> Kind {
        switch stop {
        case .permission: .permission
        case .question, .unknown: .question
        case .finished, .interrupted: .finished
        }
    }

    static func make(_ stop: AgentStop, agent: String, project: String, session: String, account: String) -> AgentNotifyText {
        let subtitle = [project, session, account].filter { !$0.isEmpty }.joined(separator: " · ")
        switch stop {
        case .permission(let tool, let subject):
            return AgentNotifyText(title: permissionTitle(tool, agent: agent), subtitle: subtitle,
                                   body: subject.isEmpty ? tool : subject)
        case .question(let question):
            return AgentNotifyText(title: T("\(agent) Has a Question", "\(agent) tem uma pergunta"), subtitle: subtitle,
                                   body: question.isEmpty ? T("It waits for your answer.", "Espera a sua resposta.") : question)
        case .finished(let reply):
            return AgentNotifyText(title: T("\(agent) Finished", "\(agent) terminou"), subtitle: subtitle,
                                   body: reply.isEmpty ? T("Ready for your next message.", "Pronto para a próxima mensagem.") : reply)
        case .interrupted, .unknown:
            return AgentNotifyText(title: T("\(agent) Is Waiting for You", "\(agent) espera você"), subtitle: subtitle,
                                   body: T("It stopped and waits for you.", "Parou e espera você."))
        }
    }

    /// "Claude Wants to Run a Command", "… to Edit a File", "… to Use WebFetch".
    static func permissionTitle(_ tool: String, agent: String) -> String {
        switch tool {
        case "Bash": T("\(agent) Wants to Run a Command", "\(agent) quer rodar um comando")
        case "Edit", "Write", "MultiEdit", "NotebookEdit": T("\(agent) Wants to Edit a File", "\(agent) quer editar um arquivo")
        default: T("\(agent) Wants to Use \(tool)", "\(agent) quer usar \(tool)")
        }
    }
}
