import AppKit
import Customize
import Strings
import UILooks

/// The top of the project's Settings (plan 36 phase E; redone 2026-11-19, the owner: "a hierarquia
/// visual não tá boa", too much explaining): the project as the sidebar shows it, picture, name and
/// folder with Edit… beside them, then the Sidebar section with Pinned. The app runs each change by
/// its command (project.edit, project.pin).
@MainActor
public final class ProjectSettingsLook: NSView {
    private let pin: ThemeSwitch

    public init(picture: ProjectPicture?, name: String, folder: String = "", pinned isPinned: Bool,
                edit: @escaping () -> Void, pinned: @escaping (Bool) -> Void) {
        pin = ThemeSwitch(on: isPinned, accent: DesignTokens.Project.Toggle.on, off: DesignTokens.Project.Toggle.off, label: "")
        super.init(frame: .zero)
        pin.onChange = pinned
        typealias P = DesignTokens.Project
        let preview = ProjectPreview.of(picture ?? ProjectPicture(), name: name)
        let title = FrameField.text(name, size: P.Title.fontSize, color: DesignTokens.Color.textPrimary, weight: P.Title.weight)
        var words: [NSView] = [title]
        if !folder.isEmpty { words.append(FrameField.text((folder as NSString).abbreviatingWithTildeInPath, color: P.Head.meta)) }
        let names = FrameField.column(words, gap: P.Head.titleGap)
        names.setHuggingPriority(.init(1), for: .horizontal)
        let button = DesignButton.make(T("Edit…", "Editar…"), .secondary) { edit() }
        button.toolTip = T("Name, image and color", "Nome, imagem e cor")
        let head = NSStackView(views: [preview, names, button])
        head.alignment = .centerY
        head.spacing = UILooks.pt(P.Head.gap)
        let sidebar = SettingGroup.section(T("Sidebar", "Barra lateral"), [
            SettingGroup.row(T("Pinned", "Fixado"), T("Stays in the sidebar with no terminal open.", "Fica na barra lateral sem terminal aberto."), pin),
        ])
        let column = FrameField.column([head, sidebar], gap: P.Group.sectionGap)
        for view in [head, sidebar] { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ProjectSettingsLook is created in code") }

    public override var isFlipped: Bool { true }

    var pinShown: Bool { pin.isOn }
    func clickPin() { pin.flip() }
}
