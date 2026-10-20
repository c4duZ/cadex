import AppKit

/// The building blocks every settings page uses, in the look of the Terax
/// settings: a title and subtitle, then rows of label, explanation and
/// control, centered in a column.
@MainActor
enum SettingsPage {
    static let columnWidth: CGFloat = 620

    /// A scrolling page with `title`, `subtitle` and the given rows.
    static func make(title: String, subtitle: String, rows: [NSView]) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        heading.textColor = SettingsColors.text
        let caption = NSTextField(labelWithString: subtitle)
        caption.textColor = SettingsColors.secondaryText
        let stack = NSStackView(views: [heading, caption] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(4, after: heading)
        stack.setCustomSpacing(24, after: caption)
        // A section title sits closer to its rows than to the group above.
        for (i, row) in rows.enumerated() where row.identifier == sectionID {
            if i > 0 { stack.setCustomSpacing(28, after: rows[i - 1]) }
            stack.setCustomSpacing(8, after: row)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in rows { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28),
            stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: columnWidth),
        ])
        return scroll
    }

    /// A row: the label and its explanation on the left, the control right.
    static func row(_ label: String, _ detail: String?, control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = SettingsColors.text
        var texts: [NSView] = [title]
        if let detail {
            let note = NSTextField(wrappingLabelWithString: detail)
            note.textColor = SettingsColors.secondaryText
            note.font = .systemFont(ofSize: 11)
            texts.append(note)
        }
        let left = NSStackView(views: texts)
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 2
        let row = NSStackView(views: [left, control])
        row.distribution = .fill
        row.alignment = .centerY
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return boxed(row)
    }

    private static let sectionID = NSUserInterfaceItemIdentifier("settingsSectionTitle")

    /// A section title between groups of rows.
    static func section(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = SettingsColors.secondaryText
        label.identifier = sectionID
        return label
    }

    /// Words to read, in a box like a row but without a control (how the
    /// lid works with keep awake).
    static func note(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = SettingsColors.secondaryText
        return boxed(label)
    }

    /// The rounded box around a row, as in Terax.
    static func boxed(_ content: NSView) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        box.layer?.borderColor = SettingsColors.border.cgColor
        box.layer?.backgroundColor = SettingsColors.box.cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
        ])
        return box
    }

    static func toggle(_ on: Bool, _ changed: @escaping (Bool) -> Void) -> NSSwitch {
        let control = NSSwitch()
        control.state = on ? .on : .off
        control.target = ActionBox.keep(control) { changed(control.state == .on) }
        control.action = #selector(ActionBox.fire)
        return control
    }

    static func popup(_ options: [(title: String, value: String)], selected: String, _ changed: @escaping (String) -> Void) -> NSPopUpButton {
        let control = NSPopUpButton()
        for option in options {
            control.addItem(withTitle: option.title)
            control.lastItem?.representedObject = option.value
        }
        control.selectItem(at: options.firstIndex { $0.value == selected } ?? 0)
        control.target = ActionBox.keep(control) {
            if let value = control.selectedItem?.representedObject as? String { changed(value) }
        }
        control.action = #selector(ActionBox.fire)
        return control
    }

    static func number(_ value: Double, range: ClosedRange<Double>, step: Double, format: String,
                       _ changed: @escaping (Double) -> Void) -> NSView {
        let label = NSTextField(labelWithString: String(format: format, value))
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let stepper = NSStepper()
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = step
        stepper.doubleValue = value
        stepper.target = ActionBox.keep(stepper) {
            label.stringValue = String(format: format, stepper.doubleValue)
            changed(stepper.doubleValue)
        }
        stepper.action = #selector(ActionBox.fire)
        let stack = NSStackView(views: [label, stepper])
        stack.spacing = 6
        return stack
    }

    /// A slider that reports when the drag ends, so the file is written once.
    /// `shown` turns the value into what the label prints (0.5 → 50 for a
    /// percentage); without it the label printed "0%" for 0.5.
    static func slider(_ value: Double, range: ClosedRange<Double>, format: String, shown: @escaping (Double) -> Double = { $0 },
                       _ changed: @escaping (Double) -> Void) -> NSView {
        let label = NSTextField(labelWithString: String(format: format, shown(value)))
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = SettingsColors.secondaryText
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        slider.target = ActionBox.keep(slider) {
            label.stringValue = String(format: format, shown(slider.doubleValue))
            if NSApp.currentEvent?.type == .leftMouseUp { changed(slider.doubleValue) }
        }
        slider.action = #selector(ActionBox.fire)
        let stack = NSStackView(views: [slider, label])
        stack.spacing = 8
        return stack
    }

    static func button(_ title: String, _ pressed: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.target = ActionBox.keep(button) { pressed() }
        button.action = #selector(ActionBox.fire)
        return button
    }

    static func text(_ value: String, placeholder: String, _ changed: @escaping (String) -> Void) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        field.target = ActionBox.keep(field) { changed(field.stringValue) }
        field.action = #selector(ActionBox.fire)
        return field
    }
}

/// Lets a control call a closure: AppKit controls send actions to objects.
/// The box lives as long as its control (associated object).
final class ActionBox: NSObject {
    private let body: () -> Void
    @MainActor private static var key = 0

    private init(_ body: @escaping () -> Void) { self.body = body }

    @MainActor static func keep(_ owner: NSObject, _ body: @escaping () -> Void) -> ActionBox {
        let box = ActionBox(body)
        objc_setAssociatedObject(owner, &key, box, .OBJC_ASSOCIATION_RETAIN)
        return box
    }

    @objc func fire() { body() }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
