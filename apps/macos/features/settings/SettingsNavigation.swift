import AppKit
import Icons
import Strings
import UILooks

/// The settings window's column on the left (plan 32 A): the search on top, then one row per
/// section with its icon, the open one in the right panel's chosen box (components.inspector.tree).
@MainActor
final class SettingsNavigation: NSView, NSSearchFieldDelegate {
    var onPick: ((SettingsSection) -> Void)?
    /// The words typed, at each key (empty: the search ended).
    var onSearch: ((String) -> Void)?
    private let search = NSSearchField()
    private let list = NSStackView()
    private var rows: [SettingsSection: SettingsNavRow] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Inspector.bg.cgColor
        search.placeholderString = T("Search settings", "Buscar configurações")
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searched)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        for section in SettingsSection.allCases {
            let row = SettingsNavRow(section)
            row.onPress = { [weak self] in self?.pick(section) }
            rows[section] = row
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        let field = FrameField.field(search)
        let column = FrameField.column([field, list], gap: DesignTokens.Project.Columns.listGap * 2)
        field.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        list.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        addSubview(column)
        let pad = DesignTokens.Inspector.Memory.padding
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(pad.left)),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(pad.right)),
            // Below the window's buttons, in the title bar's band (components.titleBar).
            column.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(DesignTokens.TitleBar.height)),
            widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Inspector.width) * 3 / 4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SettingsNavigation is created in code") }

    override var isFlipped: Bool { true }

    /// The open section's row is the chosen one; none while a search shows its results.
    func show(_ section: SettingsSection?) {
        for (key, row) in rows { row.chosen = key == section }
    }

    /// Empties the search (a section was picked).
    func clearSearch() { search.stringValue = "" }

    private func pick(_ section: SettingsSection) {
        clearSearch()
        onPick?(section)
    }

    @objc private func searched() { onSearch?(search.stringValue) }

    func focusSearch() { window?.makeFirstResponder(search) }
}

/// A section in the list: its icon and its name, a click opens it.
@MainActor
final class SettingsNavRow: FrameBox {
    var onPress: (() -> Void)?
    var chosen = false { didSet { paint() } }

    init(_ section: SettingsSection) {
        super.init(frame: .zero)
        typealias F = DesignTokens.Inspector.FileRow
        let icon = NSImageView(image: section.icon.image(size: UILooks.pt(DesignTokens.FontSize.prompt)))
        icon.contentTintColor = DesignTokens.Color.textSecondary
        let name = FrameField.text(section.title, color: DesignTokens.Color.textBody)
        let row = NSStackView(views: [icon, name])
        row.spacing = UILooks.pt(F.gap)
        hold(row, padding: F.padding)
        heightAnchor.constraint(equalToConstant: UILooks.pt(F.height)).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(section.title)
        paint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SettingsNavRow is created in code") }

    private func paint() {
        typealias Selected = DesignTokens.Inspector.Tree.Selected
        box(bg: chosen ? Selected.bg : nil, border: nil, radius: DesignTokens.Inspector.Commit.radius)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
}
