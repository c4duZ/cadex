import AppKit
import UILooks

/// What a tab shows while a pane is dragged by its header: every pane as a
/// gray window with only its header, gliding live to where it would be
/// (the owner's idea, 2026-10-22: "turn the panes into gray windows").
/// The real panes stay untouched behind it, so no terminal is resized until
/// the drop. The dragged pane's window has the accent outline.
@MainActor
final class PaneDragBoard: NSView {
    private var windows: [Int: CALayer] = [:]
    private let dragged: Int

    init(frame: NSRect, frames: [Int: CGRect], infos: [Int: PaneHeaderView.Info], dragged: Int, style: TabBarView.Style) {
        self.dragged = dragged
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = style.activeFill.blended(withFraction: 0.55, of: .black)?.cgColor
        for (id, frame) in frames {
            let window = Self.window(infos[id], style: style, dragged: id == dragged)
            window.frame = frame.insetBy(dx: 4, dy: 4)
            Self.place(window)
            layer?.addSublayer(window)
            windows[id] = window
        }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneDragBoard is created in code") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The windows glide to `frames`, overshooting a little (0.3 s).
    func show(_ frames: [Int: CGRect]) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.34, 1.3, 0.64, 1))
        for (id, window) in windows {
            if let frame = frames[id] {
                window.frame = frame.insetBy(dx: 4, dy: 4)
                Self.place(window)
            }
        }
        CATransaction.commit()
    }

    /// Fades out, then leaves.
    func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.removeFromSuperview() })
    }

    private static let headerHeight: CGFloat = 26

    /// A gray window: a rounded body, a header strip with the icon's
    /// place and the name.
    private static func window(_ info: PaneHeaderView.Info?, style: TabBarView.Style, dragged: Bool) -> CALayer {
        let window = CALayer()
        window.backgroundColor = style.activeFill.cgColor
        window.cornerRadius = 10
        window.borderWidth = dragged ? 2 : 1
        window.borderColor = (dragged ? style.accent : NSColor.white.withAlphaComponent(0.08)).cgColor
        window.shadowOpacity = 0.3
        window.shadowRadius = 8
        window.shadowOffset = CGSize(width: 0, height: -2)
        let strip = CALayer()
        strip.name = "strip"
        strip.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        window.addSublayer(strip)
        let title = CATextLayer()
        title.name = "title"
        title.string = info?.title ?? ""
        title.font = UILooks.font(12, weight: .medium)
        title.fontSize = UILooks.pt(12)
        title.foregroundColor = (dragged ? style.text : style.secondaryText).cgColor
        title.truncationMode = .end
        title.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        window.addSublayer(title)
        return window
    }

    /// The strip and the name follow the window's size.
    private static func place(_ window: CALayer) {
        let bounds = window.bounds
        for layer in window.sublayers ?? [] {
            switch layer.name {
            case "strip": layer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
            case "title": layer.frame = CGRect(x: 12, y: 6, width: max(bounds.width - 24, 0), height: 16)
            default: break
            }
        }
    }
}
