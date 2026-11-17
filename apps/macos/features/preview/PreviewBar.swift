import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The preview's bar as the PreviewOne and PreviewMany mockups draw it (plan 28 phase E;
/// components.preview): it is the pane's header (the pane draws no other), 40 pt with its line,
/// back, forward and reload small and dim, the address in its box with the page's dot (green
/// loaded, gray loading, red failed), "Pick element" in blue, and the page's sizes (desktop, phone).
@MainActor
enum PreviewBar {
    typealias B = DesignTokens.Preview

    /// A small dim icon button of the bar.
    static func icon(_ icon: Icon, _ tip: String) -> NSButton {
        let button = NSButton(image: icon.image(size: UILooks.pt(B.Url.dot * 2)), target: nil, action: nil)
        button.isBordered = false
        button.contentTintColor = DesignTokens.Color.textTertiary
        HoverTip.attach(tip, to: button)
        button.widthAnchor.constraint(equalToConstant: UILooks.pt(B.Url.height - B.Url.dot)).isActive = true
        return button
    }

    /// The address in its box, the page's dot before it.
    static func urlBox(_ field: NSTextField, dot: NSView) -> NSView {
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = UILooks.font(B.Url.fontSize)
        field.textColor = B.Url.color
        field.setContentHuggingPriority(.init(1), for: .horizontal)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = UILooks.pt(B.Url.dot) / 2
        dot.widthAnchor.constraint(equalToConstant: UILooks.pt(B.Url.dot)).isActive = true
        dot.heightAnchor.constraint(equalToConstant: UILooks.pt(B.Url.dot)).isActive = true
        let box = NSStackView(views: [dot, field])
        box.spacing = UILooks.pt(B.Bar.gap)
        box.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(B.Bar.padding.left), bottom: 0, right: UILooks.pt(B.Bar.padding.right))
        box.wantsLayer = true
        box.layer?.cornerRadius = UILooks.pt(B.Url.radius)
        box.layer?.backgroundColor = B.Url.bg.cgColor
        box.layer?.borderColor = B.Url.border.cgColor
        box.layer?.borderWidth = DesignTokens.Stroke.hairline
        box.heightAnchor.constraint(equalToConstant: UILooks.pt(B.Url.height)).isActive = true
        // A stack's own hugging, not the view's: the box takes the bar's free room (it hugged
        // "http://", 2026-11-17).
        box.setHuggingPriority(.init(1), for: .horizontal)
        box.setContentHuggingPriority(.init(1), for: .horizontal)
        return box
    }

    /// "Pick element": the blue chip; lit (the stronger fill) while picking.
    static func pickChip(_ button: NSButton, picking: Bool) {
        typealias P = B.Pick
        button.isBordered = false
        button.wantsLayer = true
        button.image = Icon.crosshair.image(size: UILooks.pt(P.fontSize))
        button.imagePosition = .imageLeading
        button.contentTintColor = P.color
        button.attributedTitle = NSAttributedString(string: " " + T("Pick element", "Escolher elemento"), attributes: [
            .font: UILooks.font(P.fontSize, weight: P.weight), .foregroundColor: P.color,
        ])
        button.layer?.cornerRadius = UILooks.pt(P.radius)
        button.layer?.backgroundColor = (picking ? P.color.withAlphaComponent(0.28) : P.bg).cgColor
        let width = button.attributedTitle.size().width + UILooks.pt(P.fontSize + P.padding.left + P.padding.right)
        if let old = button.constraints.first(where: { $0.firstAttribute == .width }) { old.constant = width } else {
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        button.heightAnchor.constraint(equalToConstant: UILooks.pt(B.Url.height)).isActive = true
    }

    /// The page's dot: what the page is doing.
    static func dotColor(loading: Bool, failed: Bool) -> NSColor {
        failed ? DesignTokens.Color.stateFailed : loading ? DesignTokens.Color.stateIdle : DesignTokens.Color.stateDone
    }

    /// The width a phone gives a page.
    static let phoneWidth: CGFloat = 390 // token-exempt: the iPhone's width in points, not a design value
}

extension PreviewDocument {
    /// The bar, the progress line and the page; the bar is the pane's header (no other is drawn).
    func layoutBar() {
        let reload = PreviewBar.icon(.arrowClockwise, T("Reload", "Recarregar"))
        for (button, selector) in [(back, #selector(backPressed)), (forward, #selector(forwardPressed)),
                                   (reload, #selector(reloadPressed)), (pick, #selector(pickPressed)),
                                   (desktop, #selector(desktopPressed)), (phone, #selector(phonePressed))] {
            button.target = self
            button.action = selector
        }
        back.isEnabled = false
        forward.isEnabled = false
        address.delegate = self
        address.placeholderString = "http://localhost:3000"
        PreviewBar.pickChip(pick, picking: false)
        progress.style = .bar
        progress.isIndeterminate = false
        progress.controlSize = .small
        progress.isHidden = true
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.isHidden = true
        let bar = NSStackView(views: [back, forward, reload, PreviewBar.urlBox(address, dot: dot), pick, desktop, phone]
                              + (Self.extraBarItems?(self) ?? []))
        bar.spacing = UILooks.pt(PreviewBar.B.Bar.gap)
        // .fill: the address box takes the room left (gravity areas kept every piece at its size).
        bar.distribution = .fill
        bar.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(PreviewBar.B.Bar.padding.left), bottom: 0,
                                      right: UILooks.pt(PreviewBar.B.Bar.padding.right))
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = PreviewBar.B.Bar.borderBottom.cgColor
        for v in [bar, line, progress, web, overlay, message] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        let fullWidth = [web.leadingAnchor.constraint(equalTo: view.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.trailingAnchor)]
        let phoneWidth = [web.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                          web.widthAnchor.constraint(equalToConstant: PreviewBar.phoneWidth)]
        sizes = (fullWidth, phoneWidth)
        NSLayoutConstraint.activate(fullWidth + [
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(PreviewBar.B.Bar.height)),
            line.topAnchor.constraint(equalTo: bar.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
            progress.topAnchor.constraint(equalTo: line.bottomAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.glyph),
            web.topAnchor.constraint(equalTo: progress.bottomAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.topAnchor.constraint(equalTo: web.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: web.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: web.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: web.bottomAnchor),
            message.centerXAnchor.constraint(equalTo: web.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: web.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: web.widthAnchor, constant: -40),
        ])
        showSize()
        showDot(loading: false, failed: false)
    }

    /// The page as a desktop or a phone shows it (the mockup's sizes).
    func showSize() {
        NSLayoutConstraint.deactivate(phoneSized ? sizes.full : sizes.phone)
        NSLayoutConstraint.activate(phoneSized ? sizes.phone : sizes.full)
        desktop.contentTintColor = phoneSized ? DesignTokens.Color.textTertiary : DesignTokens.Color.textPrimary
        phone.contentTintColor = phoneSized ? DesignTokens.Color.textPrimary : DesignTokens.Color.textTertiary
    }

    func showDot(loading: Bool, failed: Bool) {
        dot.layer?.backgroundColor = PreviewBar.dotColor(loading: loading, failed: failed).cgColor
    }

    @objc func backPressed() { goBack() }
    @objc func forwardPressed() { goForward() }
    @objc func reloadPressed() { reload() }
    @objc func desktopPressed() { phoneSized = false; showSize() }
    @objc func phonePressed() { phoneSized = true; showSize() }
    @objc func pickPressed() {
        if runCommand?("preview.pick-element") != true { togglePicking() }
    }
}
