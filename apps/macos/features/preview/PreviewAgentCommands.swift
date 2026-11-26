import CommandPalette
import Strings

/// The agent's browser as one command, `preview.agent` with `action=`
/// (docs/adr/0025-agent-drives-preview.md): goto, wait, snapshot, click,
/// fill, press, scroll, screenshot. One command, not eight in the owner's
/// ⌘K; the tools of `cadex mcp` and `cadex browser` all come here. And the
/// owner's preview.stop-agent (Esc on the tab).
public enum PreviewAgentCommands {
    /// `tab`: the preview the asking agent drives (nil: none yet);
    /// `open`: a new preview beside its terminal, for its first goto.
    @MainActor
    public static func all(tab: @escaping @MainActor (CommandRequest) -> PreviewDocument?,
                           open: @escaping @MainActor (CommandRequest) -> PreviewDocument?,
                           enabled: @escaping @MainActor () -> Bool,
                           active: @escaping @MainActor () -> PreviewDocument?) -> [Command] {
        [
            Command(id: "preview.agent", title: T("Show the Agent's Preview", "Mostrar o preview do agente"),
                    keywords: ["agent", "browser", "preview", "agente", "navegador"], category: .view,
                    action: .run { active()?.focus() })
                .acceptingLater("action=<goto|wait|snapshot|click|fill|press|scroll|screenshot|console|notes> [url= selector= timeout= ref= text= key= target=]") { request, reply in
                    guard enabled() else { return reply(.failed("the agent's browser is off in Cadex")) }
                    run(request, tab: tab, open: open, reply: reply)
                },
            Command(id: "preview.stop-agent", title: T("Stop the Agent on This Preview", "Parar o agente neste preview"),
                    keywords: ["agent", "stop", "esc", "agente", "parar"], category: .view,
                    action: .run { active()?.agent.stop() },
                    unavailableReason: { active()?.agent.isAttached == true ? nil : T("No agent on this preview", "Nenhum agente neste preview") }),
        ]
    }

    @MainActor
    static func run(_ request: CommandRequest, tab: (CommandRequest) -> PreviewDocument?, open: (CommandRequest) -> PreviewDocument?,
                    reply answer: @escaping @MainActor (CommandReply) -> Void) {
        let action = request["action"] ?? ""
        let found = action == "goto" && request["url"]?.isEmpty == false ? tab(request) ?? open(request) : tab(request)
        // The page keeps a window while the agent acts, also with the owner on another tab.
        let giveBack = found?.agent.lendWindow() ?? {}
        let reply: @MainActor (CommandReply) -> Void = { giveBack(); answer($0) }
        if action == "goto" {
            guard let url = request["url"], !url.isEmpty else { return reply(.failed("url= is needed")) }
            guard let doc = found else { return reply(.failed("the preview could not open")) }
            return doc.agent.goto(url, reply: reply)
        }
        guard let doc = found else { return reply(.failed("no page yet: call browser_goto first")) }
        let agent = doc.agent
        switch action {
        case "wait": agent.wait(selector: request["selector"], timeout: request["timeout"].flatMap(Double.init) ?? 10, reply: reply)
        case "snapshot": agent.snapshot(reply: reply)
        case "click": request["ref"].map { agent.click($0, reply: reply) } ?? reply(.failed("ref= is needed"))
        case "fill":
            guard let ref = request["ref"], let text = request["text"] else { return reply(.failed("ref= and text= are needed")) }
            agent.fill(ref, text: text, reply: reply)
        case "press": request["key"].map { agent.press($0, reply: reply) } ?? reply(.failed("key= is needed"))
        case "scroll": agent.scroll(request["target"] ?? "down", reply: reply)
        case "screenshot": agent.screenshot(reply: reply)
        case "console": agent.console(reply: reply)
        case "notes": reply(.ok(doc.notesForAgent()))
        default: reply(.failed("action is one of goto, wait, snapshot, click, fill, press, scroll, screenshot, console, notes"))
        }
    }
}
