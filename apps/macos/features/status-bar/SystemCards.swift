import AppKit
import Darwin
import Menus
import Strings
import UILooks

/// The CPU, RAM and Cadex memory cards (docs/spec/status-bar.md, Os cartões): the stats in parts,
/// this user's busiest processes and what runs in Cadex, by terminal. The processes are read only
/// while one of these cards is open, with the stats' 2 s.
@MainActor
public enum SystemCards {
    /// A terminal of Cadex: its foreground process group, its name ("cadex · terminal 2") and
    /// how to go to it. Given by the app.
    public struct Terminal {
        public var group: pid_t
        public var name: String
        public var open: () -> Void

        public init(group: pid_t, name: String, open: @escaping () -> Void) {
            self.group = group
            self.name = name
            self.open = open
        }
    }

    static var terminals: () -> [Terminal] = { [] }
    static var activityMonitor: () -> Void = {}
    private static var openCards = 0
    private(set) static var processes: [ProcessTable.Process] = []

    /// A card opened or closed: the processes are read only while one is open.
    static func cardOpened(_ open: Bool) {
        openCards = max(0, openCards + (open ? 1 : -1))
        if openCards == 0 {
            processes = []
            ProcessTable.shared.reset()
        } else if open, processes.isEmpty {
            processes = ProcessTable.shared.sample()
            sampledAt = Date()
        }
    }

    /// A new reading of the stats: the processes again, while a card is open. The three items get
    /// the same reading: one sample per reading, or the processor share would cover milliseconds.
    static func tick() {
        guard openCards > 0, Date().timeIntervalSince(sampledAt) > 1.5 else { return }
        processes = ProcessTable.shared.sample()
        sampledAt = Date()
    }
    private static var sampledAt = Date.distantPast

    static func cpu(_ r: SystemStats.Reading?, close: @escaping () -> Void) -> NSView {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        let user = r?.cpuUser ?? 0, system = r?.cpuSystem ?? 0
        var blocks: [StatusCard.Block] = [
            .header("CPU", detail: String(format: "load %.2f · %d cores", load[0], cores)),
            .big(r?.cpu.map { String(format: "%.0f%%", $0) } ?? "–",
                 caption: String(format: T("%.1f%% user · %.1f%% system", "%.1f%% usuário · %.1f%% sistema"), user, system)),
            .bar([(user / 100, DesignTokens.Color.stateWorking), (system / 100, DesignTokens.Color.stateReview)]),
        ]
        let top = processes.filter { $0.cpu != nil }.sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }.prefix(5)
        blocks += [.section(T("Your busiest processes", "Seus processos mais ocupados"))]
        if top.isEmpty { blocks.append(.note(T("Measuring…", "Medindo…"))) }
        blocks += [.rows(top.map { p in StatusCard.Row(p.name, detail: where_(p), value: String(format: "%.0f%%", p.cpu ?? 0), action: open(p)) })]
        blocks += inCadex({ $0.compactMap(\.cpu).reduce(0, +) }, format: { String(format: "%.1f%%", $0) })
        blocks += [.note(T("System processes (WindowServer and others) show only in Activity Monitor.",
                           "Os processos do sistema (WindowServer e outros) só aparecem no Monitor de Atividade.")),
                   .actions([StatusCard.Action(T("Open Activity Monitor", "Abrir o Monitor de Atividade"), run: activityMonitor)])]
        return StatusCard.build(blocks, close: close)
    }

    static func ram(_ r: SystemStats.Reading?, close: @escaping () -> Void) -> NSView {
        let total = Double(max(r?.ramTotal ?? 1, 1))
        let gb = 1_073_741_824.0
        let pressure = r?.pressure ?? 1
        let level = pressure >= 4 ? T("critical", "crítica") : pressure >= 2 ? T("warning", "atenção") : T("normal", "normal")
        let top = processes.sorted { $0.memory > $1.memory }.prefix(5)
        let blocks: [StatusCard.Block] = [
            .header(T("Memory", "Memória"), detail: T("pressure: ", "pressão: ") + level, warn: pressure >= 2),
            .big(String(format: "%.1f", Double(r?.ramUsed ?? 0) / gb),
                 caption: String(format: T("of %.0f GB in use", "de %.0f GB em uso"), total / gb)),
            .bar([(Double(r?.ramApp ?? 0) / total, DesignTokens.Color.stateWorking), (Double(r?.ramWired ?? 0) / total, DesignTokens.Color.stateNeeds),
                  (Double(r?.ramCompressed ?? 0) / total, DesignTokens.Color.stateReview)]),
            .legend([(T("App ", "Apps ") + SystemStats.sizeText(r?.ramApp ?? 0), DesignTokens.Color.stateWorking),
                     (T("Wired ", "Fixa ") + SystemStats.sizeText(r?.ramWired ?? 0), DesignTokens.Color.stateNeeds),
                     (T("Compressed ", "Comprimida ") + SystemStats.sizeText(r?.ramCompressed ?? 0), DesignTokens.Color.stateReview)]),
            .section(T("Your largest processes", "Seus maiores processos")),
            .rows(top.map { p in StatusCard.Row(p.name, detail: where_(p), value: SystemStats.sizeText(p.memory), action: open(p)) }),
            .actions([StatusCard.Action(T("Open Activity Monitor", "Abrir o Monitor de Atividade"), run: activityMonitor)]),
        ]
        return StatusCard.build(blocks, close: close)
    }

    static func cadex(_ r: SystemStats.Reading?, close: @escaping () -> Void) -> NSView {
        let me = getpid()
        let helpers = processes.filter { $0.parent == me && !groups.keys.contains($0.group) }
        let inTerminals = processes.filter { groups.keys.contains($0.group) }.map(\.memory).reduce(0, +)
        let own = r?.own ?? 0
        let all = own + helpers.map(\.memory).reduce(0, +) + inTerminals
        var blocks: [StatusCard.Block] = [
            .header("Cadex", detail: T("the app and what it runs", "o app e o que ele roda")),
            .big(SystemStats.sizeText(own), caption: T("the app · ", "o app · ") + SystemStats.sizeText(all) + T(" with its terminals", " com os terminais")),
            .section(T("Cadex itself", "O próprio Cadex")),
            .rows([StatusCard.Row("Cadex", detail: T("the app", "o app"), value: SystemStats.sizeText(own))]
                  + helpers.sorted { $0.memory > $1.memory }.map { StatusCard.Row($0.name, value: SystemStats.sizeText($0.memory)) }),
        ]
        blocks += inCadex({ Double($0.map(\.memory).reduce(0, +)) }, format: { SystemStats.sizeText(UInt64($0)) })
        blocks += [.actions([StatusCard.Action(T("Open Activity Monitor", "Abrir o Monitor de Atividade"), run: activityMonitor)])]
        return StatusCard.build(blocks, close: close)
    }

    /// The terminals with a program running, by their total, busiest first.
    private static func inCadex(_ total: ([ProcessTable.Process]) -> Double, format: (Double) -> String) -> [StatusCard.Block] {
        let rows = terminals().compactMap { terminal -> (Double, StatusCard.Row)? in
            let mine = processes.filter { $0.group == terminal.group }
            guard let first = mine.first(where: { $0.pid == terminal.group }) ?? mine.first else { return nil }
            let sum = total(mine)
            return (sum, StatusCard.Row(first.name, detail: terminal.name, value: format(sum), action: terminal.open))
        }.sorted { $0.0 > $1.0 }.prefix(6).map(\.1)
        return rows.isEmpty ? [] : [.section(T("In Cadex's terminals", "Nos terminais do Cadex")), .rows(rows)]
    }

    private static var groups: [pid_t: Terminal] {
        Dictionary(terminals().map { ($0.group, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// "cadex · terminal 2" for a process in one of Cadex's terminals.
    private static func where_(_ p: ProcessTable.Process) -> String? {
        if p.pid == getpid() { return T("this app", "este app") }
        return groups[p.group]?.name
    }

    /// A process in a terminal of Cadex: the click goes to the terminal.
    private static func open(_ p: ProcessTable.Process) -> (() -> Void)? {
        groups[p.group]?.open
    }
}
