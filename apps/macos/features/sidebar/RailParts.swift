import AppKit
import Strings
import Icons
import StateGlyph
import UILooks

/// A project's tile in the rail (components.rail.tile): the mark on the project's color, a soft
/// halo around the chosen one (the owner, 2026-11-18: a white ring made it look thicker than the
/// others; the halo keeps its size), the state badge in the top right corner and the open dot.
@MainActor
final class RailTile: NSView {
    typealias T = DesignTokens.Rail.Tile
    let project: RailProject
    var onPress: (() -> Void)?
    /// A right click: the app's menu for this project, shown at the pointer.
    var onMenu: ((NSEvent) -> Void)?
    /// An image file dropped on the tile (it becomes the project's picture).
    var onDropImage: ((URL) -> Void)?
    private let face = NSView()
    private let picture = NSImageView()
    private let mark = NSTextField(labelWithString: "")
    private let ring = NSView()
    private let badge = NSView()
    private let dot = NSView()

    /// The tile and room for its halo.
    static var outer: CGFloat { UILooks.pt(T.size + T.Chosen.halo * 2) }

    init(project: RailProject, chosen: Bool) {
        self.project = project
        super.init(frame: .zero)
        let size = UILooks.pt(T.size)
        face.wantsLayer = true
        face.layer?.cornerRadius = UILooks.pt(T.radius)
        face.layer?.backgroundColor = (project.tint.map { NSColor(srgbRed: $0[0], green: $0[1], blue: $0[2], alpha: 1) } ?? T.bg).cgColor // token-exempt: the project's own color, from the app
        mark.stringValue = project.mark
        mark.font = project.emoji?.isEmpty == false ? UILooks.font(T.emojiSize) : UILooks.font(T.fontSize, weight: T.weight)
        // The picture fills the face, cut by its corners.
        face.layer?.masksToBounds = true
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.image = project.image.flatMap { NSImage(contentsOfFile: $0) }
        picture.isHidden = picture.image == nil
        mark.isHidden = !picture.isHidden
        mark.textColor = T.color
        mark.alignment = .center
        ring.wantsLayer = true
        ring.layer?.cornerRadius = UILooks.pt(T.radius + T.Chosen.halo)
        ring.layer?.borderWidth = UILooks.pt(T.Chosen.halo)
        ring.layer?.borderColor = T.Chosen.color.cgColor
        ring.isHidden = !chosen
        // The badge is the app's state glyph on a disc of the rail's ground (the ring spins while
        // working, needs has its halo): a plain dot told working from needs by color alone (UX
        // audit, 2026-11-18).
        badge.wantsLayer = true
        badge.layer?.cornerRadius = UILooks.pt(T.Badge.size) / 2
        badge.layer?.backgroundColor = T.Badge.borderColor.cgColor
        badge.isHidden = project.badge == nil
        let glyph = StateGlyphView(size: UILooks.pt(T.Badge.size - T.Badge.border * 2), state: project.badge)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(glyph)
        NSLayoutConstraint.activate([glyph.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                                     glyph.centerYAnchor.constraint(equalTo: badge.centerYAnchor)])
        dot.wantsLayer = true
        dot.layer?.cornerRadius = UILooks.pt(T.Open.size) / 2
        dot.layer?.backgroundColor = T.Open.color.cgColor
        dot.isHidden = !project.open
        for view in [ring, face, mark, badge, dot] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        picture.translatesAutoresizingMaskIntoConstraints = false
        face.addSubview(picture)
        let badgeSize = UILooks.pt(T.Badge.size)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.outer),
            heightAnchor.constraint(equalToConstant: Self.outer),
            ring.topAnchor.constraint(equalTo: topAnchor),
            ring.bottomAnchor.constraint(equalTo: bottomAnchor),
            ring.leadingAnchor.constraint(equalTo: leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: trailingAnchor),
            face.centerXAnchor.constraint(equalTo: centerXAnchor),
            face.centerYAnchor.constraint(equalTo: centerYAnchor),
            face.widthAnchor.constraint(equalToConstant: size),
            face.heightAnchor.constraint(equalToConstant: size),
            picture.topAnchor.constraint(equalTo: face.topAnchor),
            picture.bottomAnchor.constraint(equalTo: face.bottomAnchor),
            picture.leadingAnchor.constraint(equalTo: face.leadingAnchor),
            picture.trailingAnchor.constraint(equalTo: face.trailingAnchor),
            mark.centerXAnchor.constraint(equalTo: face.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: face.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),
            badge.centerXAnchor.constraint(equalTo: face.trailingAnchor),
            badge.centerYAnchor.constraint(equalTo: face.topAnchor),
            dot.widthAnchor.constraint(equalToConstant: UILooks.pt(T.Open.size)),
            dot.heightAnchor.constraint(equalToConstant: UILooks.pt(T.Open.size)),
            dot.centerXAnchor.constraint(equalTo: face.centerXAnchor),
            // Under the halo, not on it.
            dot.topAnchor.constraint(equalTo: face.bottomAnchor, constant: UILooks.pt(T.Open.offset)),
        ])
        // The state in words too, never color alone (UX audit, 2026-11-18).
        let said = project.name + (project.badge.map { " · " + $0.words } ?? "")
        toolTip = said
        setAccessibilityRole(.button)
        setAccessibilityLabel(said)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("RailTile is created in code") }

    var pictureShown: Bool { !picture.isHidden }
    var markText: String { mark.stringValue }

    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }

    // An image file dragged onto the tile: copy, to become the project's picture.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.droppedImage(sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = Self.droppedImage(sender) else { return false }
        onDropImage?(url)
        return true
    }

    /// The image file being dragged, if it is one (the tile and the Work list's project line).
    static func droppedImage(_ sender: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: ["public.image"]]
        return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    var chosen: Bool { !ring.isHidden }

    // The whole box takes the click: the icon's image view caught it and, in a window not yet
    // key, ate the first one (plan 36 phase A, a click on Files did nothing).
    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHidden && frame.contains(point) ? self : nil
    }
    var badgeShown: Bool { !badge.isHidden }
    var dotShown: Bool { !dot.isHidden }

    override var mouseDownCanMoveWindow: Bool { false }
    // The first click of an inactive window counts (the owner's clicks were eaten, plan 34).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Past a few points the press is a drag that reorders (plan 36 phase E); the rail moves it.
    var onDrag: ((NSEvent, Bool) -> Void)?
    private let press = RailPress()
    override func mouseDown(with event: NSEvent) { press.down(event) }
    override func mouseDragged(with event: NSEvent) {
        if onDrag != nil, press.moved(event) { onDrag?(event, false) }
    }
    override func mouseUp(with event: NSEvent) {
        if press.up() { onDrag?(event, true); return }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}

/// A button of the rail (components.rail.button): an icon, lit under the pointer and while its
/// page shows; the click runs its command (ADR 0005).
@MainActor
final class RailButton: NSView {
    typealias B = DesignTokens.Rail.Button
    let command: String
    var onPress: (() -> Void)?
    private let glyph = NSImageView()
    private var hovering = false { didSet { restyle() } }
    var lit = false { didSet { restyle() } }

    // The whole box takes the click: the icon's image view caught it and, in a window not yet
    // key, ate the first one (plan 36 phase A, a click on Files did nothing).
    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHidden && frame.contains(point) ? self : nil
    }

    init(command: String, icon: Icon, tip: String) {
        self.command = command
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(B.radius)
        glyph.image = icon.fittedImage(size: UILooks.pt(B.icon))
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: UILooks.pt(B.width)),
            heightAnchor.constraint(equalToConstant: UILooks.pt(B.height)),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = tip
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("RailButton is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    // Past a few points the press is a drag that reorders (plan 36 phase E); the rail moves it.
    var onDrag: ((NSEvent, Bool) -> Void)?
    private let press = RailPress()
    override func mouseDown(with event: NSEvent) { press.down(event) }
    override func mouseDragged(with event: NSEvent) {
        if onDrag != nil, press.moved(event) { onDrag?(event, false) }
    }
    override func mouseUp(with event: NSEvent) {
        if press.up() { onDrag?(event, true); return }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }

    private func restyle() {
        layer?.backgroundColor = lit || hovering ? B.Lit.bg.cgColor : nil
        glyph.contentTintColor = lit || hovering ? B.Lit.color : B.color
    }
}

/// The narrow strip's requests (components.workSidebar.queue, collapsed): an amber box with the
/// number of agents waiting on you; the click goes there (plan 38 G).
@MainActor
final class RailAsking: NSView {
    typealias Q = DesignTokens.WorkSidebar.Queue
    var onPress: (() -> Void)?
    private let number = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Q.bg.cgColor
        layer?.borderColor = Q.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(DesignTokens.WorkSidebar.Edge.radius)
        number.font = UILooks.font(Q.Row.fontSize, weight: Q.Head.weight)
        number.textColor = Q.Head.color
        number.alignment = .center
        number.translatesAutoresizingMaskIntoConstraints = false
        addSubview(number)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Rail.Tile.size)),
            heightAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.WorkSidebar.Edge.height)),
            number.centerXAnchor.constraint(equalTo: centerXAnchor),
            number.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("RailAsking is created in code") }

    func say(_ count: Int) {
        number.stringValue = "\(count)"
        let words = count == 1 ? T("1 agent needs you", "1 agente precisa de você") : T("\(count) agents need you", "\(count) agentes precisam de você")
        toolTip = words
        setAccessibilityLabel(words)
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}
