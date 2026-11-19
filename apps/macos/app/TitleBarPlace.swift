import AppKit
import Icons
import Strings
import UILooks

/// Where you are, at the start of the top bar (components.place; ADR 0039): the project's avatar,
/// "project › task ▾". The click opens the place's menu (the app's entries: switch project or task,
/// back to main, the project's page).
@MainActor
final class TitleBarPlace: NSView {
    typealias P = DesignTokens.Place
    var onPress: (() -> Void)?
    private let avatar = NSView()
    private let mark = NSTextField(labelWithString: "")
    private let picture = NSImageView()
    private let words = NSTextField(labelWithString: "")
    private var hovering = false { didSet { layer?.backgroundColor = hovering ? P.hover.cgColor : nil } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(P.radius)
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = UILooks.pt(P.Avatar.radius)
        avatar.layer?.masksToBounds = true
        mark.font = UILooks.font(P.Avatar.fontSize, weight: P.Avatar.weight)
        mark.textColor = P.Name.color
        mark.alignment = .center
        picture.imageScaling = .scaleProportionallyUpOrDown
        for view in [mark, picture] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            avatar.addSubview(view)
        }
        words.lineBreakMode = .byTruncatingMiddle
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [avatar, words])
        stack.spacing = UILooks.pt(P.gap)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let size = UILooks.pt(P.Avatar.size)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.pt(P.height)),
            avatar.widthAnchor.constraint(equalToConstant: size),
            avatar.heightAnchor.constraint(equalToConstant: size),
            mark.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            picture.topAnchor.constraint(equalTo: avatar.topAnchor),
            picture.bottomAnchor.constraint(equalTo: avatar.bottomAnchor),
            picture.leadingAnchor.constraint(equalTo: avatar.leadingAnchor),
            picture.trailingAnchor.constraint(equalTo: avatar.trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(P.padding.left)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(P.padding.right)),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.popUpButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarPlace is created in code") }

    /// The place: the project (its picture, emoji or two letters, on its color) and the task, if any.
    func show(project: String, task: String?, mark text: String, image: String?, tint: NSColor?) {
        let line = NSMutableAttributedString(string: project, attributes: [
            .font: UILooks.font(P.Name.fontSize, weight: P.Name.weight), .foregroundColor: P.Name.color])
        if let task {
            line.append(NSAttributedString(string: "  ›  ", attributes: [.font: UILooks.font(P.Name.fontSize), .foregroundColor: P.separator]))
            line.append(NSAttributedString(string: task, attributes: [
                .font: UILooks.font(P.Name.fontSize, weight: P.Name.weight), .foregroundColor: P.Name.color]))
        }
        line.append(NSAttributedString(string: "  ▾", attributes: [.font: UILooks.font(P.Chevron.fontSize), .foregroundColor: P.Chevron.color]))
        words.attributedStringValue = line
        mark.stringValue = text
        picture.image = image.flatMap { NSImage(contentsOfFile: $0) }
        picture.isHidden = picture.image == nil
        mark.isHidden = !picture.isHidden
        avatar.layer?.backgroundColor = (tint ?? DesignTokens.Color.bgButton).cgColor
        let said = [project, task].compactMap { $0 }.joined(separator: " › ")
        toolTip = said
        setAccessibilityLabel(said)
    }

    var said: String { words.stringValue }

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
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}

/// Review, inside a task (components.place.review): a button, not a tab, after a thin divider.
@MainActor
final class TitleBarReview: NSView {
    typealias R = DesignTokens.Place.Review
    var onPress: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderColor = R.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(R.radius)
        let icon = NSImageView(image: Icon.gitDiff.fittedImage(size: UILooks.pt(R.fontSize)))
        icon.contentTintColor = R.color
        let label = NSTextField(labelWithString: T("Review", "Revisar"))
        label.font = UILooks.font(R.fontSize, weight: R.weight)
        label.textColor = R.color
        let stack = NSStackView(views: [icon, label])
        stack.spacing = UILooks.pt(R.gap)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.pt(R.height)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(R.padding.left)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(R.padding.right)),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = T("Review the task's changes", "Revisar as mudanças da tarefa")
        setAccessibilityRole(.button)
        setAccessibilityLabel(T("Review", "Revisar"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarReview is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}
