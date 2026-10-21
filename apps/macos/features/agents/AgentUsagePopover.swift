import AppKit
import Strings
import UILooks

/// Every account of every provider, over the status bar: logo, name,
/// plan, the session's and the week's bars with when they reset. In the
/// menus' look (rounded, the theme's panel), never taking the keyboard.
@MainActor
final class AgentUsagePopover: NSPanel {
    var onEnter: (() -> Void)?
    var onLeave: (() -> Void)?
    private(set) var hasPointer = false
    private let stack = NSStackView()
    private let box = PointerBox()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient]
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.onEnter = { [weak self] in
            self?.hasPointer = true
            self?.onEnter?()
        }
        box.onExit = { [weak self] in
            self?.hasPointer = false
            self?.onLeave?()
        }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            box.widthAnchor.constraint(equalToConstant: UILooks.pt(300)),
        ])
        contentView = box
    }

    override var canBecomeKey: Bool { false }

    func render(colors: AgentColors) {
        box.layer?.backgroundColor = colors.panel.cgColor
        box.layer?.borderColor = colors.border.cgColor
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let usage = AgentUsageController.shared
        let accounts = usage.accounts()
        if accounts.isEmpty {
            stack.addArrangedSubview(AgentText.label(T("No account on this Mac.", "Nenhuma conta neste Mac."), size: 12, color: colors.secondary))
        }
        for account in accounts {
            let logo = NSImageView(image: account.logo.image(size: UILooks.pt(14)))
            logo.contentTintColor = colors.text
            let plan = usage.plans[account.dir].map { " · " + $0.capitalized } ?? ""
            let head = NSStackView(views: [logo, AgentText.label(account.name, size: 12, weight: .semibold, color: colors.text),
                                           AgentText.label(plan, size: 11, color: colors.secondary)])
            head.spacing = 6
            var views: [NSView] = [head]
            switch usage.states[account.dir] ?? .loading {
            case .ready(let numbers, let at):
                views += AgentUsageRows.bars(numbers, colors: colors, dim: false)
                if account.provider == .codex {
                    views.append(AgentText.label(T("as of ", "em ") + AgentResetTime.text(at), size: 11, color: colors.secondary))
                }
            case .failed(let numbers, _):
                if let numbers { views += AgentUsageRows.bars(numbers, colors: colors, dim: true) }
                views.append(AgentText.label(T("Could not read now", "Não deu para ler agora"), size: 11, color: colors.secondary))
            case .expired:
                views.append(AgentText.label(T("Login expired", "Login vencido"), size: 11, color: colors.secondary))
            case .noLogin:
                views.append(AgentText.label(T("No login", "Sem login"), size: 11, color: colors.secondary))
            case .loading:
                views.append(AgentText.label(T("Reading…", "Lendo…"), size: 11, color: colors.secondary))
            }
            let part = NSStackView(views: views)
            part.orientation = .vertical
            part.alignment = .leading
            part.spacing = 4
            for view in views.dropFirst() { view.widthAnchor.constraint(equalToConstant: UILooks.pt(272)).isActive = true }
            stack.addArrangedSubview(part)
        }
        box.layoutSubtreeIfNeeded()
        setContentSize(box.fittingSize)
    }

    /// Above the item, its left edge lined up, kept on screen.
    func show(above view: NSView) {
        guard let window = view.window else { return }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        var origin = NSPoint(x: rect.minX - 8, y: rect.maxY + 6)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 6), screen.maxX - frame.width - 6)
            origin.y = min(origin.y, screen.maxY - frame.height - 6)
        }
        setFrameOrigin(origin)
        orderFront(nil)
    }
}

/// The popover's ground: says when the pointer comes in and goes out.
private final class PointerBox: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
