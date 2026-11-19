import AppKit
import Strings
import Tabs
import UILooks

/// A project's own settings, a page beside its Overview (plan 32 D; the owner, 2026-11-18: the
/// settings window keeps the defaults, "e a gente tem uma tela do projeto para a gente mexer
/// nisso"): the sections the app gives (the memory's
/// .ai-memory.toml first). This feature does not know what they set; each section writes its own.
@MainActor
public final class ProjectSettingsDocument: TabDocument {
    public let folder: String
    private let sections: () -> [NSView]
    private let scroll = NSScrollView()
    private let column = FrameField.column([], gap: DesignTokens.Project.Group.sectionGap)
    public var onChange: (() -> Void)?

    public init(folder: String, sections: @escaping () -> [NSView]) {
        self.folder = folder
        self.sections = sections
        build()
        show()
    }

    /// Under "project:", so the tabs group it with the project's other pages (TabsGroups).
    public static func identity(for folder: String) -> String { "project:settings:" + folder }
    public var identity: String { Self.identity(for: folder) }
    public var title: String { T("Settings", "Configurações") }
    public var view: NSView { scroll }
    public var hasUnsavedChanges: Bool { false }
    public var isPage: Bool { true }

    /// Back on the tab: read again (the file may have changed in a terminal or a commit).
    public func focus() { show() }
    /// Built again: a setting changed from elsewhere (⌘K's memory.toggle-project, plan 35 I).
    public func reload() { show() }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}

    private func build() {
        let document = ProjectSettingsContent()
        document.wantsLayer = true
        document.layer?.backgroundColor = DesignTokens.Color.bgWindow.cgColor
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(column)
        scroll.documentView = document
        scroll.drawsBackground = true
        scroll.backgroundColor = DesignTokens.Color.bgWindow
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let pad = DesignTokens.Project.padding
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            column.topAnchor.constraint(equalTo: document.topAnchor, constant: UILooks.pt(pad.top)),
            column.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -UILooks.pt(pad.bottom)),
            column.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            column.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Sheet.newTaskWidth)),
        ])
    }

    private func show() {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // The project's own head is the first section's (ProjectSettingsLook): no title or
        // explanation of its own (the owner, 2026-11-19: "overexplaining").
        for view in sections() {
            column.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
    }
}

/// The page's document view, top-down.
final class ProjectSettingsContent: NSView {
    override var isFlipped: Bool { true }
}
