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
    public var overview = MemoryOverviewActions()
    /// The tab closed: the sidebar goes back to Work.
    public var closed: () -> Void = {}
    public init() {}
}

/// The Memória page (plan 40 C): a page of the app in the center, like Automations; the sidebar
/// shows its sections meanwhile (MemoryPanelNav). This phase draws Visão geral; the other sections
/// say in one line that they come soon.
@MainActor
public final class MemoryPanelDocument: TabDocument {
    public static let identity = "memory:panel"
    private let actions: MemoryPanelActions
    private let host = FrameBox()
    public let overview: MemoryOverviewView
    public private(set) var section: MemoryPanelSection = .projects
    public var view: NSView { host }
    public var title: String { T("Memory", "Memória") }
    public var identity: String { Self.identity }
    public var hasUnsavedChanges: Bool { false }
    public var onChange: (() -> Void)?
    public var isPage: Bool { true }
    /// The last read gave data: the overview shows it.
    public private(set) var loaded = false

    public init(actions: MemoryPanelActions) {
        self.actions = actions
        overview = MemoryOverviewView(actions: actions.overview)
        host.wantsLayer = true
        show(.projects)
    }

    public func focus() {
        refresh()
        if section == .projects { host.window?.makeFirstResponder(overview) }
    }

    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() { actions.closed() }

    /// The section in the center: the overview, or the one line of a section still to come.
    public func show(_ next: MemoryPanelSection) {
        section = next
        guard next.isBuilt else { return place(PanelEmpty.view(next.title, T("Coming soon.", "Em breve."))) }
        place(overview)
        refresh()
    }

    /// The overview read again (the page shown, a section picked).
    public func refresh() {
        guard section == .projects else { return }
        actions.load { [weak self] load in
            guard let self, self.section == .projects else { return }
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

    private func place(_ view: NSView) {
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
