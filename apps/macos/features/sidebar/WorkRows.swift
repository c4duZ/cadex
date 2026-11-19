import AppKit
import Icons
import Menus
import StateGlyph
import UILooks

/// A project's avatar (components.workSidebar.avatar): its picture, else its emoji, else two letters
/// on its color.
@MainActor
final class WorkAvatar: NSView {
    typealias A = DesignTokens.WorkSidebar.Avatar

    init(_ project: WorkProject) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(A.radius)
        layer?.masksToBounds = true
        let tint = project.tint.map { NSColor(srgbRed: $0[0], green: $0[1], blue: $0[2], alpha: 1) } // token-exempt: the project's own color, from the app
        layer?.backgroundColor = (tint ?? DesignTokens.Color.bgButton).cgColor
        if let path = project.image, let image = NSImage(contentsOfFile: path) {
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyUpOrDown
            pin(view)
        } else {
            let mark = NSTextField(labelWithString: project.emoji.flatMap { $0.isEmpty ? nil : $0 } ?? project.initials)
            mark.font = UILooks.font(A.fontSize, weight: A.weight)
            mark.textColor = DesignTokens.Color.textPrimary
            mark.alignment = .center
            mark.translatesAutoresizingMaskIntoConstraints = false
            addSubview(mark)
            NSLayoutConstraint.activate([mark.centerXAnchor.constraint(equalTo: centerXAnchor),
                                         mark.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: UILooks.pt(A.size)),
                                     heightAnchor.constraint(equalToConstant: UILooks.pt(A.size))])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkAvatar is created in code") }

    private func pin(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor)])
    }
}

/// One line of the Work list (components.workSidebar.row): an optional caret, an optional avatar,
/// the name and, on the right, what it holds (the state glyph and the terminals, "nada aberto", or
/// the amber count of requests). The whole line takes the click; lit for the place you are in.
@MainActor
final class WorkRow: NSView {
    typealias R = DesignTokens.WorkSidebar.Row
    /// The trailing info.
    enum Meta: Equatable { case terminals(GlyphState?, Int), nothing(String), waiting(Int), none }

    var onPress: (() -> Void)?
    var onCaret: (() -> Void)?
    var rightMenu: (() -> [MenuEntry])?
    /// Past a few points the press is a drag (a project's line, plan 38: the order of the rail stays);
    /// the sidebar gets each move and the release.
    var onDrag: ((NSEvent, Bool) -> Void)?
    /// An image file dropped on a project's line becomes its picture, as on the strip's tile (plan 38,
    /// left from phase H): set, the line takes file drops.
    var onDropImage: ((URL) -> Void)? {
        didSet { onDropImage == nil ? unregisterDraggedTypes() : registerForDraggedTypes([.fileURL]) }
    }
    private let press = RailPress()
    let title: String
    private(set) var selected = false
    private let caret = NSImageView()
    private var hovering = false { didSet { paint() } }

    init(title: String, caret: Bool?, avatar: NSView?, bold: Bool, fontSize: CGFloat, meta: Meta, selected: Bool) {
        self.title = title
        self.selected = selected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(R.radius)
        var views: [NSView] = []
        if let caret {
            // Phosphor's carets: the ▸ and ▾ characters drew as dots at this size (seen in the app).
            self.caret.image = (caret ? Icon.caretDown : Icon.caretRight).fittedImage(size: UILooks.pt(R.Caret.size))
            self.caret.contentTintColor = R.Caret.color
            self.caret.widthAnchor.constraint(equalToConstant: UILooks.pt(R.Caret.size)).isActive = true
            views.append(self.caret)
        }
        if let avatar { views.append(avatar) }
        let name = NSTextField(labelWithString: title)
        name.font = UILooks.font(fontSize, weight: bold ? R.Project.weight : .regular)
        name.textColor = selected ? R.Selected.color : bold ? R.Project.color : R.color
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        views.append(name)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        views.append(spacer)
        views += Self.metaViews(meta)
        let stack = NSStackView(views: views)
        stack.spacing = UILooks.pt(R.gap)
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.rowHeight(R.height)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(R.padding.left)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(R.padding.right)),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = title
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        paint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkRow is created in code") }

    static func metaViews(_ meta: Meta) -> [NSView] {
        typealias M = R.Meta
        typealias Q = DesignTokens.WorkSidebar.Queue.Count
        switch meta {
        case .none: return []
        case .nothing(let words):
            let text = NSTextField(labelWithString: words)
            text.font = UILooks.font(M.fontSize, weight: M.weight)
            text.textColor = R.dim
            return [text]
        case .terminals(let state, let count):
            var views: [NSView] = []
            if let state { views.append(StateGlyphView(size: UILooks.pt(DesignTokens.StateGlyph.sizes[1]), state: state)) }
            if count > 0 {
                let number = NSTextField(labelWithString: "\(count)")
                number.font = UILooks.monospacedDigits(M.fontSize, weight: M.weight)
                number.textColor = M.color
                views.append(number)
            }
            let box = NSStackView(views: views)
            box.spacing = UILooks.pt(M.gap)
            return [box]
        case .waiting(let count):
            let pill = NSTextField(labelWithString: "\(count)")
            pill.font = UILooks.font(Q.fontSize, weight: Q.weight)
            pill.textColor = Q.color
            pill.alignment = .center
            pill.wantsLayer = true
            pill.layer?.backgroundColor = Q.bg.cgColor
            pill.layer?.cornerRadius = UILooks.pt(Q.radius)
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: UILooks.pt(Q.padding.left * 2) + 8).isActive = true
            return [pill]
        }
    }

    private func paint() {
        layer?.backgroundColor = selected ? R.Selected.bg.cgColor : hovering ? R.Selected.bg.withAlphaComponent(0.5).cgColor : nil // token-exempt: the hover is the selection at half
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { press.down(event) }
    override func mouseDragged(with event: NSEvent) {
        if onDrag != nil, press.moved(event) { onDrag?(event, false) }
    }
    override func mouseUp(with event: NSEvent) {
        if press.up() { onDrag?(event, true); return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        // The caret's room (the padding and the caret) folds; the rest goes.
        if onCaret != nil, point.x < UILooks.pt(R.padding.left + R.Caret.size + R.gap) { return onCaret?() ?? () }
        onPress?()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDropImage != nil && RailTile.droppedImage(sender) != nil ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let onDropImage, let url = RailTile.droppedImage(sender) else { return false }
        onDropImage(url)
        return true
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let entries = rightMenu?(), !entries.isEmpty else { return super.rightMouseDown(with: event) }
        PopupMenu.show(entries, at: convert(event.locationInWindow, from: nil), in: self)
    }
}
