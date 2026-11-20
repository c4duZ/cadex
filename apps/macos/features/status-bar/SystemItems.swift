import AppKit
import Icons
import Menus
import Strings

/// The items made of SystemStats: RAM, CPU and Cadex's memory. Each one watches the stats only
/// while it can be seen; the pointer over it opens its card (SystemCards), whose button runs
/// `click`, the command that opens Activity Monitor. A click on the item does nothing: it opened
/// Activity Monitor when you only meant to read the card (the owner, 2026-11-20). `terminals` are Cadex's terminals with a program, for
/// the cards' "In Cadex" (given by the app; this feature imports no other).
@MainActor
public enum SystemItems {
    public static func all(click: @escaping () -> Void, terminals: @escaping () -> [SystemCards.Terminal] = { [] }) -> [StatusItem] {
        SystemCards.terminals = terminals
        SystemCards.activityMonitor = click
        return [
            item("ram", T("RAM", "RAM"), T("Memory in use on this Mac, every 2 s", "Memória em uso neste Mac, a cada 2 s"), .memory, click,
                 card: SystemCards.ram) { r, label in
                label.text = SystemStats.memoryText(r.ramUsed, of: r.ramTotal)
                // Amber as Activity Monitor's pressure leaves normal (the owner, 2026-11-18), red when critical.
                label.tint = r.pressure >= 4 ? .systemRed : r.pressure >= 2 ? .systemOrange : nil
                label.setTip(T("Memory in use: ", "Memória em uso: ") + SystemStats.sizeText(r.ramUsed)
                             + T(" of ", " de ") + SystemStats.sizeText(r.ramTotal))
            },
            item("cpu", "CPU", T("Processor in use on this Mac, every 2 s", "Processador em uso neste Mac, a cada 2 s"), .cpu, click,
                 card: SystemCards.cpu) { r, label in
                label.text = r.cpu.map { String(format: "%.0f%%", $0) } ?? "–"
                label.tint = (r.cpu ?? 0) >= 90 ? .systemOrange : nil
            },
            item("cadexMemory", T("Cadex memory", "Memória do Cadex"), T("What Cadex itself uses, every 2 s", "O que o próprio Cadex usa, a cada 2 s"),
                 .appWindow, click, card: SystemCards.cadex) { r, label in
                label.text = SystemStats.sizeText(r.own)
                label.setTip(T("Memory used by Cadex", "Memória usada pelo Cadex"))
            },
        ]
    }

    private static func item(_ id: String, _ title: String, _ subtitle: String, _ icon: Icon, _ click: @escaping () -> Void,
                             card build: @escaping (SystemStats.Reading?, @escaping () -> Void) -> NSView,
                             show: @escaping (SystemStats.Reading, StatusLabel) -> Void) -> StatusItem {
        let label = StatusLabel(icon: icon, tip: title)
        var last: SystemStats.Reading?
        var card: HoverCard?
        card = HoverCard(over: label) { build(last, { card?.close() }) }
        card?.onOpenChange = { open in SystemCards.cardOpened(open) }
        let item = StatusItem(id: id, title: title, subtitle: subtitle, icon: icon, side: .right, view: label)
        var token: UUID?
        item.onVisible = { [weak label] visible in
            if visible {
                token = SystemStats.shared.watch { reading in
                    last = reading
                    guard let label else { return }
                    show(reading, label)
                    SystemCards.tick()
                    card?.refresh()
                }
            } else if let id = token {
                SystemStats.shared.stop(id)
                token = nil
                card?.close()
            }
        }
        return item
    }
}
