import AppKit

/// A sheet in the new frame's face (plan 31 B; the New Task sheet's measures, components.sheet and
/// components.newTask): the window dimmed, a raised panel near the top with the title, a line that
/// says what will happen, the form, and a footer with Cancel and the main button. Esc cancels; ⌘↩
/// (and ↩ outside a text area) accepts. It replaces the system alert for the app's forms (New Run,
/// New Automation, Add Task, Dispatch, Dependencies), whose controls did not look like the app.
@MainActor
public final class FrameSheet: NSView {
    typealias NT = DesignTokens.NewTask
    private let panel = FrameBox()
    private let done: @MainActor (Bool) -> Void
    private var keys: Any?
    private var first: NSView?
    private var finished = false

    /// Shows the sheet over the window's content; `done` gets true for the main button.
    @discardableResult
    /// `cancel`: the Cancel button's words, in the app's language (this module has no strings).
    public static func show(in window: NSWindow, title: String, text: String?, body: NSView, primary: String, cancel: String, first: NSView? = nil,
                            done: @escaping @MainActor (Bool) -> Void) -> FrameSheet? {
        guard let host = window.contentView else { return nil }
        let sheet = FrameSheet(title: title, text: text, body: body, primary: primary, cancel: cancel, done: done)
        sheet.first = first
        sheet.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(sheet, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: host.leadingAnchor), sheet.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            sheet.topAnchor.constraint(equalTo: host.topAnchor), sheet.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        return sheet
    }

    private init(title: String, text: String?, body: NSView, primary: String, cancel: String, done: @escaping @MainActor (Bool) -> Void) {
        self.done = done
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Sheet.scrim.cgColor
        build(title: title, text: text, body: body, primary: primary, cancel: cancel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FrameSheet is created in code") }

    public override var isFlipped: Bool { true }
    /// The scrim takes the clicks: nothing behind the sheet is reachable while it shows.
    public override func mouseDown(with event: NSEvent) {}

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keys { NSEvent.removeMonitor(keys); self.keys = nil }
        guard let window else { return }
        if let first { window.makeFirstResponder(first) }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.keyCode == 53 { self.finish(false); return nil }
            let enter = event.keyCode == 36 || event.keyCode == 76
            if enter, event.modifierFlags.contains(.command) || !(self.window?.firstResponder is NSTextView && self.window?.firstResponder !== self.window?.fieldEditor(false, for: nil)) {
                self.finish(true)
                return nil
            }
            return event
        }
    }

    /// Closes the sheet as a press of its buttons would (the tests answer through it).
    public func finish(_ accepted: Bool) {
        guard !finished else { return }
        finished = true
        if let keys { NSEvent.removeMonitor(keys); self.keys = nil }
        removeFromSuperview()
        done(accepted)
    }

    private func build(title: String, text: String?, body: NSView, primary: String, cancel: String) {
        panel.box(bg: DesignTokens.Sheet.bg, border: DesignTokens.Sheet.border, radius: DesignTokens.Sheet.radius)
        if let shadow = DesignTokens.Sheet.shadow.first {
            panel.layer?.masksToBounds = false
            panel.layer?.shadowColor = shadow.color.cgColor
            panel.layer?.shadowOpacity = 1
            panel.layer?.shadowRadius = UILooks.pt(shadow.layerRadius)
            panel.layer?.shadowOffset = shadow.offset
        }
        let heading = FrameField.text(title, size: DesignTokens.Sheet.Title.fontSize, color: DesignTokens.Color.textPrimary,
                                      weight: DesignTokens.Sheet.Title.weight)
        var top: [NSView] = [heading]
        if let text, !text.isEmpty { top.append(FrameField.wrapping(text, color: NT.Subtitle.color)) }
        let words = FrameField.column(top, gap: NT.Frame.headerGap)
        body.translatesAutoresizingMaskIntoConstraints = false
        let column = FrameField.column([words, body], gap: NT.Frame.labelTop)
        let inset = UILooks.pt(NT.Frame.inset)
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        let foot = footer(primary: primary, cancel: cancel)
        for view in [content, foot] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(view)
        }
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: UILooks.pt(NT.Frame.headerTop)),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            words.widthAnchor.constraint(equalTo: column.widthAnchor), body.widthAnchor.constraint(equalTo: column.widthAnchor),
            content.topAnchor.constraint(equalTo: panel.topAnchor), content.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            foot.topAnchor.constraint(equalTo: content.bottomAnchor, constant: UILooks.pt(NT.Footer.marginTop)),
            foot.leadingAnchor.constraint(equalTo: panel.leadingAnchor), foot.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            foot.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Sheet.newTaskWidth)),
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            // Near the top as New Task, but never taller than the window: a long form starts higher.
            panel.topAnchor.constraint(lessThanOrEqualTo: topAnchor, constant: UILooks.pt(NT.Frame.top)),
            panel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: UILooks.pt(NT.Frame.inset)),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -UILooks.pt(NT.Frame.inset)),
        ])
        let high = panel.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(NT.Frame.top))
        high.priority = .defaultLow
        high.isActive = true
    }

    /// Cancel and the main button on the right, the line on top (New Task's footer).
    private func footer(primary: String, cancel title: String) -> NSView {
        typealias Ft = NT.Footer
        let cancel = DesignButton.make(title, .secondary, height: Ft.buttonHeight) { [weak self] in self?.finish(false) }
        let main = DesignButton.make(primary, .primary, height: Ft.buttonHeight) { [weak self] in self?.finish(true) }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [spacer, cancel, main])
        row.spacing = UILooks.pt(Ft.gap)
        let pad = Ft.padding
        row.edgeInsets = NSEdgeInsets(top: UILooks.pt(pad.top), left: UILooks.pt(pad.left), bottom: UILooks.pt(pad.bottom), right: UILooks.pt(pad.right))
        let box = NSView()
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Ft.borderTop.cgColor
        for view in [line, row] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: box.topAnchor), line.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: box.trailingAnchor), line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
            row.topAnchor.constraint(equalTo: line.bottomAnchor), row.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: box.trailingAnchor), row.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }
}
