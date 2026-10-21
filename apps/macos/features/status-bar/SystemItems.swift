import AppKit
import Icons
import Strings

/// The items made of SystemStats: RAM, CPU and Cadex's memory. Each one
/// watches the stats only while it can be seen; a click runs `click`, the
/// command that opens Activity Monitor.
@MainActor
public enum SystemItems {
    public static func all(click: @escaping () -> Void) -> [StatusItem] {
        [
            item("ram", T("RAM", "RAM"), T("Memory in use on this Mac, every 2 s", "Memória em uso neste Mac, a cada 2 s"), .memory, click) { r, label in
                label.text = SystemStats.memoryText(r.ramUsed, of: r.ramTotal)
                let share = r.ramTotal == 0 ? 0 : Double(r.ramUsed) / Double(r.ramTotal)
                // The warning colors only when memory runs short.
                label.tint = share >= 0.9 ? .systemRed : share >= 0.8 ? .systemOrange : nil
                label.setTip(T("Memory in use: ", "Memória em uso: ") + SystemStats.sizeText(r.ramUsed)
                             + T(" of ", " de ") + SystemStats.sizeText(r.ramTotal))
            },
            item("cpu", "CPU", T("Processor in use on this Mac, every 2 s", "Processador em uso neste Mac, a cada 2 s"), .cpu, click) { r, label in
                label.text = r.cpu.map { String(format: "%.0f%%", $0) } ?? "–"
                label.tint = (r.cpu ?? 0) >= 90 ? .systemOrange : nil
            },
            item("cadexMemory", T("Cadex memory", "Memória do Cadex"), T("What Cadex itself uses, every 2 s", "O que o próprio Cadex usa, a cada 2 s"), .appWindow, click) { r, label in
                label.text = SystemStats.sizeText(r.own)
                label.setTip(T("Memory used by Cadex", "Memória usada pelo Cadex"))
            },
        ]
    }

    private static func item(_ id: String, _ title: String, _ subtitle: String, _ icon: Icon, _ click: @escaping () -> Void,
                             show: @escaping (SystemStats.Reading, StatusLabel) -> Void) -> StatusItem {
        let label = StatusLabel(icon: icon, tip: title)
        label.onClick = click
        let item = StatusItem(id: id, title: title, subtitle: subtitle, icon: icon, side: .right, view: label)
        var token: UUID?
        item.onVisible = { [weak label] visible in
            if visible {
                token = SystemStats.shared.watch { reading in if let label { show(reading, label) } }
            } else if let id = token {
                SystemStats.shared.stop(id)
                token = nil
            }
        }
        return item
    }
}
