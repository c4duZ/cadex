import AppKit
import UILooks

/// The project's tile as the rail draws it (components.rail.tile): the picture over the face, or
/// the emoji, or the letter, on the project's color.
@MainActor
final class ProjectPreview: NSView {
    typealias T = DesignTokens.Rail.Tile
    private let picture = NSImageView()
    private let mark = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(T.radius)
        layer?.masksToBounds = true
        picture.imageScaling = .scaleProportionallyUpOrDown
        mark.alignment = .center
        mark.textColor = T.color
        for view in [picture, mark] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: UILooks.pt(T.size)),
            heightAnchor.constraint(equalToConstant: UILooks.pt(T.size)),
            picture.topAnchor.constraint(equalTo: topAnchor), picture.bottomAnchor.constraint(equalTo: bottomAnchor),
            picture.leadingAnchor.constraint(equalTo: leadingAnchor), picture.trailingAnchor.constraint(equalTo: trailingAnchor),
            mark.centerXAnchor.constraint(equalTo: centerXAnchor), mark.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ProjectPreview is created in code") }

    func show(image: NSImage?, mark text: String, emoji: Bool, color: NSColor?) {
        picture.image = image
        picture.isHidden = image == nil
        mark.isHidden = image != nil
        mark.stringValue = text
        mark.font = emoji ? UILooks.font(T.emojiSize) : UILooks.font(T.fontSize, weight: T.weight)
        layer?.backgroundColor = (color ?? T.bg).cgColor
    }

    var shownMark: String? { mark.isHidden ? nil : mark.stringValue }

    /// The tile of a project's picture and name, for the pages.
    static func of(_ picture: ProjectPicture, name: String) -> ProjectPreview {
        let preview = ProjectPreview()
        let letter = name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "•"
        let emoji = picture.emoji?.isEmpty == false ? picture.emoji : nil
        preview.show(image: picture.image.flatMap { NSImage(contentsOfFile: $0) }, mark: emoji ?? letter, emoji: emoji != nil, color: picture.tint)
        return preview
    }
}

/// One color to pick (a work color, or none): a round chip, the chosen one with the rail's halo.
@MainActor
final class ColorSwatch: NSView {
    typealias T = DesignTokens.Rail.Tile
    let color: NSColor?
    var onPress: (() -> Void)?
    var chosen = false { didSet { layer?.borderColor = (chosen ? T.Chosen.color : NSColor.clear).cgColor } }

    init(color: NSColor?, tip: String) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        let size = UILooks.pt(DesignTokens.Inspector.Scope.Button.size)
        layer?.cornerRadius = size / 2
        layer?.borderWidth = UILooks.pt(T.Chosen.halo)
        layer?.borderColor = NSColor.clear.cgColor
        // No color: the tile's own background, a line across it.
        layer?.backgroundColor = (color ?? T.bg).cgColor
        if color == nil {
            let slash = NSView()
            slash.wantsLayer = true
            slash.layer?.backgroundColor = DesignTokens.Color.textMuted.cgColor
            slash.translatesAutoresizingMaskIntoConstraints = false
            addSubview(slash)
            slash.frameCenterRotation = 45
            NSLayoutConstraint.activate([
                slash.centerXAnchor.constraint(equalTo: centerXAnchor), slash.centerYAnchor.constraint(equalTo: centerYAnchor),
                slash.widthAnchor.constraint(equalToConstant: DesignTokens.Stroke.glyph),
                slash.heightAnchor.constraint(equalToConstant: size * 0.6),
            ])
        }
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        toolTip = tip
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ColorSwatch is created in code") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}
