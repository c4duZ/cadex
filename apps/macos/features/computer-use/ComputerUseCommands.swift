import CommandPalette
import Foundation
import Strings

/// Computer use's commands (docs/spec/computer-use.md): the owner's toggle,
/// revoke, stop and permissions; and the agent's one command,
/// computer-use.agent with `action=` (list_apps, get_state, click, type,
/// set_value, scroll, screenshot), which `cadex mcp` and `cadex computer` use.
public enum ComputerUseCommands {
    /// `toggle`: the app turns computerUse.enabled over, explaining and
    /// opening System Settings when it turns on; `openPermissions` opens them.
    @MainActor
    public static func all(toggle: @escaping @MainActor () -> Void, openPermissions: @escaping @MainActor () -> Void) -> [Command] {
        let controller = ComputerUseController.shared
        return [
            Command(id: "computer-use.toggle", title: T("Turn Computer Use On or Off", "Ligar ou desligar o computer use"),
                    keywords: ["computer use", "accessibility", "agent", "apps", "acessibilidade", "agente"], category: .terminal,
                    action: .run { toggle() }),
            Command(id: "computer-use.open-permissions", title: T("Open Computer Use Permissions", "Abrir as permissões do computer use"),
                    keywords: ["computer use", "accessibility", "screen recording", "permissions", "acessibilidade", "permissões"], category: .terminal,
                    action: .run { openPermissions() }),
            Command(id: "computer-use.revoke-apps", title: T("Forget Apps Allowed to Agents", "Esquecer os apps permitidos aos agentes"),
                    keywords: ["computer use", "revoke", "apps", "revogar", "permissões"], category: .terminal,
                    action: .run { controller.revokeApps() }),
            Command(id: "computer-use.stop", title: T("Stop the Agent in Other Apps", "Parar o agente nos outros apps"),
                    keywords: ["computer use", "stop", "agent", "parar", "agente"], category: .terminal,
                    action: .run { controller.stop() }),
            Command(id: "computer-use.agent", title: T("Computer Use Settings", "Configurações do computer use"),
                    keywords: ["computer use", "agent", "agente"], category: .terminal,
                    action: .run { openPermissions() })
                .acceptingLater("action=<list_apps|get_state|click|type|set_value|scroll|screenshot> [app= index= text= value= direction=]") { request, reply in
                    run(request, controller, reply: reply)
                },
        ]
    }

    @MainActor
    static func run(_ request: CommandRequest, _ controller: ComputerUseController, reply: @escaping @MainActor (CommandReply) -> Void) {
        let action = request["action"] ?? ""
        if action == "list_apps" { return reply(controller.listApps()) }
        guard let app = request["app"], !app.isEmpty else { return reply(.failed("app= is needed (computer_list_apps)")) }
        if action == "get_state" { return controller.getState(app, reply: reply) }
        if action == "screenshot" { return controller.screenshot(app, reply: reply) }
        guard let index = request["index"].flatMap({ Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "#"))) }) else {
            return reply(.failed("index= from computer_get_state is needed"))
        }
        switch action {
        case "click": controller.click(app, index: index, reply: reply)
        case "type": controller.type(app, index: index, text: request["text"] ?? "", reply: reply)
        case "set_value": controller.setValue(app, index: index, value: request["value"] ?? "", reply: reply)
        case "scroll": controller.scroll(app, index: index, down: request["direction"] != "up", reply: reply)
        default: reply(.failed("action is one of list_apps, get_state, click, type, set_value, scroll, screenshot"))
        }
    }
}
