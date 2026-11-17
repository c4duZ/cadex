import AppKit
import Agents
import Terminal

/// The permission an agent waits for, at the foot of its pane (plan 28 phase D; the Pane mockup):
/// the bell's request for this terminal, with Allow and Deny. Both read AgentAttention, so an
/// answer in one closes the other. Only requests the hook waits on (`canAnswer`): the ones seen
/// only by the agent's report have nothing to answer, and the bell takes the owner to the tab.
extension WindowSession {
    func startPanePermissions() {
        panePermissionWatch = AgentAttention.shared.watch { [weak self] in self?.showPanePermissions() }
    }

    private func showPanePermissions() {
        guard let projects else { return }
        let requests = AgentAttention.shared.cards.filter { $0.kind == .permission && $0.canAnswer }
        for project in projects.projects {
            for terminal in project.tabs.allTerminals {
                let key = AppDelegate.key(terminal)
                let request = requests.first { $0.key == key }
                if (terminal.footCard as? AgentPermissionCard)?.requestID == request?.id { continue }
                terminal.footCard = request.map { request in
                    AgentPermissionCard(request, allow: { AgentAttention.shared.approve(request.id) },
                                        deny: { AgentAttention.shared.deny(request.id) })
                }
            }
        }
    }
}
