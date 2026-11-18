import AppKit
import UILooks
import Icons
import Menus
import Strings

/// The find bar (⌘F) over the top-right corner of the terminal: the text to
/// find, "3 de 12", previous and next, close. Enter goes to the next (older)
/// match, Shift+Enter to the previous one, Esc closes (docs/spec/terminal.md).
/// The frame's popover (components.popover; plan 31 E): raised, its line and corner.
final class TerminalFindBar: NSView, NSSearchFieldDelegate {
    var onChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    private let field = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        typealias P = DesignTokens.Popover
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(P.radius)
        layer?.backgroundColor = P.bg.cgColor
        layer?.borderColor = P.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline

        field.placeholderString = T("Find", "Buscar")
        field.delegate = self
        field.sendsSearchStringImmediately = true
        field.target = self
        field.action = #selector(fieldChanged)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        (field.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        field.font = UILooks.font(DesignTokens.FontSize.body)
        field.textColor = DesignTokens.Color.textPrimary
        countLabel.textColor = DesignTokens.Color.textMuted
        countLabel.font = UILooks.monospacedDigits(DesignTokens.FontSize.meta)

        let stack = NSStackView(views: [
            field, countLabel,
            button(.caretUp, T("Previous (⇧↩)", "Anterior (⇧↩)"), #selector(previousClicked)),
            button(.caretDown, T("Next (↩)", "Próxima (↩)"), #selector(nextClicked)),
            button(.x, T("Close (Esc)", "Fechar (Esc)"), #selector(closeClicked)),
        ])
        let pad = DesignTokens.NewTask.AgentRow.padding
        stack.spacing = UILooks.pt(DesignTokens.NewTask.Option.gap)
        stack.edgeInsets = NSEdgeInsets(top: UILooks.pt(pad.top), left: UILooks.pt(pad.left), bottom: UILooks.pt(pad.bottom), right: UILooks.pt(pad.right))
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Inspector.width) * 2 / 3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TerminalFindBar is created in code") }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    var text: String { field.stringValue }

    /// "3 de 12", T("No results", "Sem resultados"), or nothing while the field is empty.
    func showCounts(total: Int, current: Int) {
        if field.stringValue.isEmpty {
            countLabel.stringValue = ""
        } else if total == 0 {
            countLabel.stringValue = T("No results", "Sem resultados")
        } else {
            countLabel.stringValue = current > 0 ? T("\(current) of \(total)", "\(current) de \(total)") : "\(total)"
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

    private func button(_ icon: Icon, _ tip: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: icon.image(size: UILooks.pt(DesignTokens.FontSize.prompt)), target: self, action: action)
        button.contentTintColor = DesignTokens.Color.textSecondary
        button.setAccessibilityLabel(tip)
        button.isBordered = false
        HoverTip.attach(tip, to: button)
        return button
    }

    @objc private func previousClicked() { onPrevious?() }
    @objc private func nextClicked() { onNext?() }
    @objc private func closeClicked() { onClose?() }
}
