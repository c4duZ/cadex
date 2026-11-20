import AppKit
import StateGlyph
import Strings
import UILooks

/// One request in the needs-you queue (ADR 0039; plan 38 phase C): the app gathers it from the
/// open requests (the bell's), the queue only draws it and says which was clicked.
public struct WorkRequest: Equatable, Sendable {
    public var id: String
    /// Who asks: the task's or the session's name.
    public var who: String
    public var project: String
    /// What it asks, in a sentence ("wants to run npm install stripe").
    public var ask: String
    public var since: Date

    public init(id: String, who: String, project: String, ask: String, since: Date) {
        self.id = id
        self.who = who
        self.project = project
        self.ask = ask
        self.since = since
    }

    /// "now", "4 min", "2 h": how long it has waited.
    public static func waited(_ since: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(since))
        if seconds < 60 { return T("now", "agora") }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600) h"
    }
}

/// The needs-you queue (components.workSidebar.queue): an amber card on top of the sidebar, in
/// every view, only while something waits on you; each line the one who asks, how long, and what
/// it asks. A click goes to that agent's terminal, where Claude's own dialog is.
@MainActor
public final class WorkQueueView: NSView {
    typealias Q = DesignTokens.WorkSidebar.Queue
    public var onPick: ((String) -> Void)?
    private let stack = NSStackView()
    private(set) var shown: [WorkRequest] = []

    public init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Q.bg.cgColor
        layer?.borderColor = Q.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(Q.radius)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(Q.padding.top)),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(Q.padding.bottom)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(Q.padding.left)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(Q.padding.right)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkQueueView is created in code") }

    /// The requests, oldest first; redrawn only when they change.
    public func show(_ requests: [WorkRequest], now: Date = Date()) {
        shown = requests
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let head = NSTextField(labelWithString: T("NEEDS YOU", "PRECISA DE VOCÊ"))
        head.font = UILooks.font(Q.Head.fontSize, weight: Q.Head.weight)
        head.textColor = Q.Head.color
        let count = WorkRow.metaViews(.waiting(requests.count))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        add(NSStackView(views: [head, spacer] + count))
        for request in requests {
            let line = WorkQueueLine(request, now: now)
            line.onPress = { [weak self] in self?.onPick?(request.id) }
            line.setContentHuggingPriority(.defaultHigh, for: .vertical)
            stack.setCustomSpacing(UILooks.pt(Q.Row.marginTop), after: stack.arrangedSubviews.last ?? line)
            add(line)
        }
    }

    private func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

/// One request: the needs glyph, who, how long; under it, what it asks.
@MainActor
final class WorkQueueLine: NSView {
    typealias Q = DesignTokens.WorkSidebar.Queue
    var onPress: (() -> Void)?

    init(_ request: WorkRequest, now: Date) {
        super.init(frame: .zero)
        let glyph = StateGlyphView(size: UILooks.pt(DesignTokens.StateGlyph.sizes[2]), state: .needs)
        let who = NSTextField(labelWithString: request.who)
        who.font = UILooks.font(Q.Row.fontSize, weight: Q.Row.weight)
        who.textColor = Q.Row.color
        who.lineBreakMode = .byTruncatingTail
        who.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let age = NSTextField(labelWithString: WorkRequest.waited(request.since, now: now))
        age.font = UILooks.font(Q.Age.fontSize)
        age.textColor = Q.Age.color
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let top = NSStackView(views: [glyph, who, spacer, age])
        top.spacing = UILooks.pt(Q.Row.gap)
        let ask = NSTextField(wrappingLabelWithString: request.ask)
        ask.font = UILooks.font(Q.Ask.fontSize)
        ask.textColor = Q.Ask.color
        ask.maximumNumberOfLines = 2
        ask.lineBreakMode = .byTruncatingTail
        for view in [top, ask] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor),
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.trailingAnchor.constraint(equalTo: trailingAnchor),
            ask.topAnchor.constraint(equalTo: top.bottomAnchor, constant: UILooks.pt(Q.Ask.marginTop)),
            ask.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(Q.Ask.indent)),
            ask.trailingAnchor.constraint(equalTo: trailingAnchor),
            ask.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        toolTip = request.project + " › " + request.who + ": " + request.ask
        setAccessibilityRole(.button)
        setAccessibilityLabel(request.who + ", " + request.ask)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkQueueLine is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}
