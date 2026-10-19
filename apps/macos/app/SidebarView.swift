import AppKit

/// The sidebar panel's content. Empty until the explorer and source
/// control features exist (plans 4 and 6): a short note in the middle.
final class SidebarView: NSView {
    private let note = NSTextField(wrappingLabelWithString: "Arquivos e Git aparecem aqui.")

    override init(frame: NSRect) {
        super.init(frame: frame)
        note.alignment = .center
        note.font = .systemFont(ofSize: 12)
        note.translatesAutoresizingMaskIntoConstraints = false
        addSubview(note)
        NSLayoutConstraint.activate([
            note.centerXAnchor.constraint(equalTo: centerXAnchor),
            note.centerYAnchor.constraint(equalTo: centerYAnchor),
            note.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarView is created in code") }

    func setColors(secondary: NSColor) {
        note.textColor = secondary
    }
}
