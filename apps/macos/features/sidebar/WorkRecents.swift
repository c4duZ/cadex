import AppKit
import Strings
import Icons
import UILooks

/// A recent project while nothing is open (plan 38 G; ADR 0039, Nada aberto): its face as an open
/// project's, and when it was used ("yesterday", "2 days").
public struct WorkRecent: Equatable, Sendable {
    public var project: WorkProject
    public var when: String

    public init(project: WorkProject, when: String) {
        self.project = project
        self.when = when
    }
}

/// Nothing open: the sidebar lists the recents, then New Project… and Open Folder…, without the
/// Work | Files switch (there is no place to look at). A recent clicked comes back by
/// `onPickRecent`; the two rows run their commands.
extension WorkSidebarView {
    typealias R = DesignTokens.WorkSidebar

    public func showRecents(_ recents: [WorkRecent], openShortcut: String) {
        guard recents != recentsShown else { return }
        recentsShown = recents
        shown = nil
        switchRow.isHidden = true
        setFilesHidden(true)
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let label = NSTextField(labelWithString: T("RECENT", "RECENTES"))
        label.font = UILooks.font(R.Section.fontSize, weight: R.Section.weight)
        label.textColor = R.Section.color
        let labelBox = NSStackView(views: [label])
        labelBox.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(R.Section.padding.left), bottom: 0, right: 0)
        add(labelBox)
        list.setCustomSpacing(UILooks.pt(R.Section.padding.bottom), after: labelBox)
        for recent in recents {
            let row = WorkRow(title: recent.project.name, caret: nil, avatar: WorkAvatar(recent.project), bold: true,
                              fontSize: R.Row.fontSize, meta: .nothing(recent.when), selected: false)
            row.onPress = { [weak self] in self?.onPickRecent?(recent.project.id) }
            row.rightMenu = { [weak self] in self?.menuFor?(recent.project.id) ?? [] }
            add(row)
        }
        for (title, icon, key, command) in [(T("New Project…", "Novo projeto…"), Icon.plus, "", "project.create"),
                                            (T("Open Folder…", "Abrir pasta…"), Icon.folder, openShortcut, "project.new")] {
            let row = WorkRow(title: title, caret: nil, avatar: WorkIconSlot(icon), bold: false, dim: true, fontSize: R.Row.fontSize,
                              meta: key.isEmpty ? .none : .nothing(key), selected: false)
            row.onPress = { [weak self] in self?.run(command) }
            if command == "project.create" { list.setCustomSpacing(UILooks.pt(R.Section.padding.bottom), after: list.arrangedSubviews.last ?? row) }
            add(row)
        }
    }

    /// A project opened: the switch and the view come back.
    func leaveRecents() {
        guard recentsShown != nil else { return }
        recentsShown = nil
        switchRow.isHidden = false
        setMode(mode)
    }

    /// For tests: nothing open.
    var showsRecents: Bool { recentsShown != nil }
}
