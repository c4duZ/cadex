import AppKit
import Strings
import UILooks

/// The top of the project's Settings (plan 36 phase E; docs/adr/0038-rail-and-side-column.md): how
/// it shows in the rail, the picture and the name with "Edit Name and Image…", and whether it stays
/// there with no terminal (pinned). The Projects page edits nothing; this, the rail's right click
/// and ⌘K do. The app runs each change by its command.
@MainActor
public final class ProjectSettingsLook: NSView {
    private let pin: NSButton
    private let pinned: (Bool) -> Void

    public init(picture: ProjectPicture?, name: String, pinned isPinned: Bool,
                edit: @escaping () -> Void, pinned: @escaping (Bool) -> Void) {
        self.pinned = pinned
        pin = NSButton(checkboxWithTitle: T("Keep in the sidebar with no terminal open (pinned)",
                                            "Manter na barra lateral sem terminal aberto (fixado)"), target: nil, action: nil)
        super.init(frame: .zero)
        pin.state = isPinned ? .on : .off
        pin.target = self
        pin.action = #selector(pinChanged)
        let preview = ProjectPreview.of(picture ?? ProjectPicture(), name: name)
        let title = FrameField.text(name, color: DesignTokens.Color.textPrimary)
        let button = DesignButton.make(T("Edit Name and Image…", "Editar nome e imagem…"), .secondary) { edit() }
        let row = NSStackView(views: [preview, title, button])
        row.alignment = .centerY
        row.spacing = UILooks.pt(DesignTokens.Project.Head.gap)
        let column = FrameField.column([FrameField.label(T("In the sidebar", "Na barra lateral")), row, FrameField.check(pin)],
                                       gap: DesignTokens.Project.Columns.listGap)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ProjectSettingsLook is created in code") }

    public override var isFlipped: Bool { true }

    @objc private func pinChanged() { pinned(pin.state == .on) }

    var pinShown: Bool { pin.state == .on }
    func clickPin() { pin.performClick(nil) }
}
