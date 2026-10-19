import AppKit

/// The find bar (⌘F) over the top-right corner of the terminal: the text to
/// find, "3 de 12", previous and next, close. Enter goes to the next (older)
/// match, Shift+Enter to the previous one, Esc closes (docs/spec/terminal.md).
final class TerminalFindBar: NSVisualEffectView, NSSearchFieldDelegate {
    var onChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    private let field = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8

        field.placeholderString = "Buscar"
        field.delegate = self
        field.sendsSearchStringImmediately = true
        field.target = self
        field.action = #selector(fieldChanged)
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

        let stack = NSStackView(views: [
            field, countLabel,
            button("chevron.up", "Anterior (⇧↩)", #selector(previousClicked)),
            button("chevron.down", "Próxima (↩)", #selector(nextClicked)),
            button("xmark", "Fechar (Esc)", #selector(closeClicked)),
        ])
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.widthAnchor.constraint(equalToConstant: 200),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TerminalFindBar is created in code") }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    var text: String { field.stringValue }

    /// "3 de 12", "Sem resultados", or nothing while the field is empty.
    func showCounts(total: Int, current: Int) {
        if field.stringValue.isEmpty {
            countLabel.stringValue = ""
        } else if total == 0 {
            countLabel.stringValue = "Sem resultados"
        } else {
            countLabel.stringValue = current > 0 ? "\(current) de \(total)" : "\(total)"
        }
    }

    // MARK: Field

    @objc private func fieldChanged() {
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            shift ? onPrevious?() : onNext?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    // MARK: Buttons

    private func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.toolTip = tip
        return button
    }

    @objc private func previousClicked() { onPrevious?() }
    @objc private func nextClicked() { onNext?() }
    @objc private func closeClicked() { onClose?() }
}
