import AppKit
import Strings
import Tabs
import UILooks

/// What a read of the overview gave.
public enum PanelLoad: Sendable {
    case data(PanelOverviewData)
    /// The engine refused or did not answer: its words.
    case failed(String)
    /// memory.enabled is off: nothing is read.
    case off
}

/// What the Memória page asks the app; each is a command's work (ADR 0005).
@MainActor
public struct MemoryPanelActions {
    /// Reads the overview's routes; `done` on the main thread.
    public var load: (@escaping @MainActor (PanelLoad) -> Void) -> Void = { $0(.off) }
    /// Reads one panel route (`cadex memory-agent panel --path P`): the bytes, or the engine's words.
    public var read: (String, @escaping @MainActor (Result<Data, PanelReadError>) -> Void) -> Void = { _, done in done(.failure(PanelReadError(words: ""))) }
    /// Writes one panel route (`cadex memory-agent panel-post --path P`, the JSON on stdin): the
    /// answer's bytes, or the engine's words (plan 40 F, the inbox's messages).
    public var write: (String, String, @escaping @MainActor (Result<Data, PanelReadError>) -> Void) -> Void = { _, _, done in
        done(.failure(PanelReadError(words: "")))
    }
    /// A write of the inbox: the app runs its command (memory.send-message and the others, ADR 0005),
    /// which comes back to `perform`. Nil (the tests): the page performs it itself.
    public var message: ((PanelWrite) -> Void)?
    /// A guide of the Documentação: the app runs memory.open-guide (nil: the page opens it).
    public var openGuide: ((PanelGuide) -> Void)?
    /// A click that goes somewhere: the app runs memory.show-panel with the place, which comes back
    /// to `go`. Nil (the tests): the page goes itself.
    public var go: ((PanelPlace) -> Void)?
    /// ⌘[ and ⌘] in the page: memory.panel-back and memory.panel-forward (nil: the page itself).
    public var back: (() -> Void)?
    public var forward: (() -> Void)?
    public var overview = MemoryOverviewActions()
    /// A project's screens: "Abrir no Cadex", the inbox.
    public var project = PanelProjectActions()
    /// The tab closed: the sidebar goes back to Work.
    public var closed: () -> Void = {}
    public init() {}
}

/// A read that failed: the engine's words.
public struct PanelReadError: Error, Sendable {
    public var words: String
    public init(words: String) { self.words = words }
}

/// The Memória page (plan 40 C and D): a page of the app in the center, like Automations; the
/// sidebar shows its sections meanwhile (MemoryPanelNav). Visão geral and a project's screens (the
/// project, a page, its history, a session, its retrievals, an agent) are drawn; the other sections
/// say in one line that they come soon. Back and forward go through the places seen
/// (PanelNavigation.swift).
@MainActor
public final class MemoryPanelDocument: TabDocument {
    public static let identity = "memory:panel"
    let actions: MemoryPanelActions
    let host = FrameBox()
    public let overview: MemoryOverviewView
    public internal(set) var section: MemoryPanelSection = .projects
    public var view: NSView { host }
    public var title: String { T("Memory", "Memória") }
    public var identity: String { Self.identity }
    public var hasUnsavedChanges: Bool { false }
    public var onChange: (() -> Void)?
    public var isPage: Bool { true }
    /// The last read gave data: the overview shows it.
    public private(set) var loaded = false
    /// Where the page is and where it was (back and forward).
    public internal(set) var trail = PanelTrail()
    /// The screen of a project's place, once read.
    public internal(set) var screen: NSView?
    /// Counts the reads, so an older answer arriving late draws nothing.
    var generation = 0
    /// The search that opened each page, for its "Por que esta página foi recuperada?" (upstream
    /// carries it in the page's URL; here the page keeps it while the window lives).
    var recall: [PanelHitKey: PanelSearchQuery] = [:]
    /// What the last health fix did, for the health screen read again after it (plan 40 G).
    var healthSaid: String?

    public init(actions: MemoryPanelActions) {
        self.actions = actions
        overview = MemoryOverviewView(actions: actions.overview)
        host.wantsLayer = true
        show(.projects)
    }

    public func focus() {
        guard case .section = trail.current else { _ = host.window?.makeFirstResponder(screen); return }
        refresh()
        if section == .projects { host.window?.makeFirstResponder(overview) }
    }

    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() { actions.closed() }

    /// The section in the center: the overview, or the one line of a section still to come.
    public func show(_ next: MemoryPanelSection) {
        let place = PanelPlace.section(next).normalized
        guard case .section = place else { return go(place) }
        trail.go(place)
        showSection(next)
    }

    func showSection(_ next: MemoryPanelSection) {
        generation += 1
        screen = nil
        section = next
        guard next.isBuilt else { return place(PanelEmpty.view(next.title, T("Coming soon.", "Em breve."))) }
        place(overview)
        refresh()
    }

    /// The overview read again (the page shown, a section picked).
    public func refresh() {
        guard section == .projects, case .section = trail.current else { return }
        actions.load { [weak self] load in
            guard let self, self.section == .projects, case .section = self.trail.current else { return }
            switch load {
            case .data(let data):
                self.loaded = true
                self.overview.show(data)
                self.place(self.overview)
            case .failed(let words):
                // A page already drawn stays; a first read that fails says why in one line.
                if !self.loaded { self.place(PanelEmpty.view(T("Memory did not answer", "A memória não respondeu"), words)) }
            case .off:
                self.loaded = false
                self.place(PanelEmpty.view(T("Memory is off", "A memória está desligada"),
                                           T("Turn it on in Settings › Memory.", "Ligue em Ajustes › Memória.")))
            }
        }
    }

    func place(_ view: NSView) {
        guard view.superview !== host else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        host.hold(view, padding: NSEdgeInsets())
    }
}

/// A screen with nothing to list: the title and one short line (components.memoryPanel.empty).
@MainActor
enum PanelEmpty {
    static func view(_ title: String, _ line: String) -> NSView {
        let head = PanelText.line(title, size: MP.Empty.Title.fontSize, color: DesignTokens.Color.textPrimary, weight: MP.Empty.Title.weight)
        let words = PanelText.line(line, size: MP.Empty.Text.fontSize, color: MP.Empty.Text.color)
        words.toolTip = line
        let column = PanelText.column([head, words], gap: MP.Empty.gap)
        let box = PanelFlipped()
        box.hold(column, padding: MP.Page.padding)
        let outer = FrameBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(box)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: outer.topAnchor), box.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            box.bottomAnchor.constraint(lessThanOrEqualTo: outer.bottomAnchor),
        ])
        return outer
    }
}

/// Cards in rows of `columns`, each as wide as the others; the last row's empty places kept, so a
/// lone card stays a third wide (the board's grid).
@MainActor
enum PanelGrid {
    static func rows(_ cards: [NSView], columns: Int, gap: CGFloat) -> [NSView] {
        stride(from: 0, to: cards.count, by: columns).map { start in
            let slice = Array(cards[start..<min(start + columns, cards.count)])
            let fill = (slice.count..<columns).map { _ in NSView() }
            let row = NSStackView(views: slice + fill)
            row.distribution = .fillEqually
            row.alignment = .top
            row.spacing = UILooks.pt(gap)
            // Each card as tall as the row's tallest (one card's inbox chip made it taller).
            for card in slice { card.heightAnchor.constraint(equalTo: row.heightAnchor).isActive = true }
            return row
        }
    }
}
