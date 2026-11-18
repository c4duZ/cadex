import AppKit
import Customize
import UILooks

/// The building blocks every settings page uses, in the new frame's face
/// (plan 31 D; the project page's title, rows and labels, the frame's
/// controls): a title and subtitle, then rows of label, explanation and
/// control, centered in a column.
@MainActor
enum SettingsPage {
    static var columnWidth: CGFloat { UILooks.pt(DesignTokens.Sheet.newTaskWidth) }

    /// A scrolling page with `title`, `subtitle` and the given rows.
    static func make(title: String, subtitle: String, rows: [NSView]) -> NSView {
        typealias P = DesignTokens.Project
        let heading = FrameField.text(title, size: P.Title.fontSize, color: SettingsColors.text, weight: P.Title.weight)
        let caption = FrameField.text(subtitle, color: P.Head.meta)
        let stack = NSStackView(views: [heading, caption] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILooks.pt(P.Columns.listGap)
        stack.setCustomSpacing(UILooks.pt(P.Head.titleGap), after: heading)
        stack.setCustomSpacing(UILooks.pt(P.gap), after: caption)
        // A section title sits closer to its rows than to the group above.
        for (i, row) in rows.enumerated() where row.identifier == sectionID {
            if i > 0 { stack.setCustomSpacing(UILooks.pt(P.gap), after: rows[i - 1]) }
            stack.setCustomSpacing(UILooks.pt(DesignTokens.NewTask.Frame.labelBottom), after: row)
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
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: UILooks.pt(DesignTokens.Project.padding.top)),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -UILooks.pt(DesignTokens.Project.padding.bottom)),
            stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: columnWidth),
        ])
        return scroll
    }

    /// A row: the label and its explanation on the left, the control right.
    static func row(_ label: String, _ detail: String?, control: NSView) -> NSView {
        if let toggle = control as? ThemeSwitch { toggle.setAccessibilityLabel(label) }
        let title = FrameField.text(label, color: SettingsColors.text, weight: DesignTokens.FontWeight.semibold)
        var texts: [NSView] = [title]
        if let detail {
            let note = FrameField.wrapping(detail, color: SettingsColors.secondaryText)
            note.font = UILooks.font(DesignTokens.Project.Row.Meta.fontSize)
            texts.append(note)
        }
        let left = FrameField.column(texts, gap: DesignTokens.Project.Row.textGap)
        left.translatesAutoresizingMaskIntoConstraints = true
        let row = NSStackView(views: [left, control])
        row.spacing = UILooks.pt(DesignTokens.Project.Row.gap)
        row.distribution = .fill
        row.alignment = .centerY
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return boxed(row)
    }

    private static let sectionID = NSUserInterfaceItemIdentifier("settingsSectionTitle")

    /// A section title between groups of rows.
    static func section(_ text: String) -> NSView {
        let label = FrameField.label(text)
        label.identifier = sectionID
        return label
    }

    /// Words to read, in a box like a row but without a control (how the
    /// lid works with keep awake).
    static func note(_ text: String) -> NSView {
        boxed(FrameField.wrapping(text, color: SettingsColors.secondaryText))
    }

    /// The rounded box around a row.
    static func boxed(_ content: NSView) -> NSView {
        typealias R = DesignTokens.Project.Row
        let box = FrameBox()
        box.box(bg: SettingsColors.box, border: SettingsColors.border, radius: R.radius)
        box.hold(content, padding: DesignTokens.Project.Stat.padding)
        return box
    }

    /// The app's switch, the same as Customize's, in the theme's accent.
    static func toggle(_ on: Bool, _ changed: @escaping (Bool) -> Void) -> ThemeSwitch {
        let control = ThemeSwitch(on: on, accent: DesignTokens.Project.Toggle.on, off: DesignTokens.Project.Toggle.off, label: "")
        control.onChange = changed
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
        FrameField.framed(control)
        return control
    }

    static func number(_ value: Double, range: ClosedRange<Double>, step: Double, format: String,
                       _ changed: @escaping (Double) -> Void) -> NSView {
        let label = NSTextField(labelWithString: String(format: format, value))
        label.font = UILooks.monospacedDigits(DesignTokens.FontSize.meta)
        label.textColor = SettingsColors.text
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
        stack.spacing = UILooks.pt(DesignTokens.Project.Head.titleGap)
        return stack
    }

    /// A slider that reports when the drag ends, so the file is written once.
    /// `shown` turns the value into what the label prints (0.5 → 50 for a
    /// percentage); without it the label printed "0%" for 0.5.
    static func slider(_ value: Double, range: ClosedRange<Double>, format: String, shown: @escaping (Double) -> Double = { $0 },
                       _ changed: @escaping (Double) -> Void) -> NSView {
        let label = NSTextField(labelWithString: String(format: format, shown(value)))
        label.font = UILooks.monospacedDigits(DesignTokens.FontSize.caption)
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
        stack.spacing = UILooks.pt(DesignTokens.NewTask.Option.gap)
        return stack
    }

    /// The app's secondary button (components.button).
    static func button(_ title: String, _ pressed: @escaping () -> Void) -> NSButton {
        DesignButton.make(title, .secondary) { pressed() }
    }

    /// A text field in the frame's box, the width of the right panel's half.
    static func text(_ value: String, placeholder: String, _ changed: @escaping (String) -> Void) -> NSView {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.target = ActionBox.keep(field) { changed(field.stringValue) }
        field.action = #selector(ActionBox.fire)
        let box = FrameField.field(field)
        box.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Inspector.width) * 3 / 4).isActive = true
        return box
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
