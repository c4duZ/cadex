import AppKit
import Strings
import UILooks

/// The conversation's drawing: the subagent's description on top, then
/// each entry as Claude Code writes it (AgentTranscriptStyle.swift), all in
/// one text view that lays out only what is on screen. A view per entry
/// cost 25 MB for 200 of them, one layer each, whatever the log's size
/// (measured 2026-10-21).
@MainActor
final class AgentTranscriptView: NSView {
    var colors: AgentColors { didSet { redraw() } }
    private let heading: String
    private let detail: String
    private var entries: [AgentTranscriptEntry] = []
    private let scroll = NSScrollView()
    // TextKit 2 lays out only what is in view: in the release app TextKit 1
    // jumped 70 MB while opening a 34 MB log and kept +20 MB open; this keeps
    // +3 MB from the second opening on and ~1 MB once closed (make perf, 2026-10-21).
    private let text = NSTextView(usingTextLayoutManager: true)

    init(title: String, detail: String, colors: AgentColors) {
        heading = title
        self.detail = detail
        self.colors = colors
        super.init(frame: .zero)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 18, height: 18)
        text.isVerticallyResizable = true
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        redraw()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentTranscriptView is created in code") }

    var textView: NSTextView { text }

    /// New entries at the end; the view follows them if it was there.
    func append(_ new: [AgentTranscriptEntry]) {
        let atBottom = isAtBottom
        let first = entries.isEmpty
        entries += new
        if first { redraw() } else { text.textStorage?.append(drawn(new)) }
        if atBottom || first { text.scrollToEndOfDocument(nil) }
    }

    func clear() {
        entries = []
        text.textStorage?.setAttributedString(NSAttributedString())
    }

    private var isAtBottom: Bool {
        scroll.contentView.bounds.maxY >= text.frame.height - 40
    }

    private func redraw() {
        let style = AgentTranscriptStyle(colors: colors)
        let all = NSMutableAttributedString(attributedString: style.heading(heading, detail))
        if entries.isEmpty {
            all.append(NSAttributedString(string: T("Reading…", "Lendo…"), attributes: [.font: style.font, .foregroundColor: colors.secondary]))
        }
        all.append(drawn(entries))
        text.textStorage?.setAttributedString(all)
    }

    private func drawn(_ entries: [AgentTranscriptEntry]) -> NSAttributedString {
        let style = AgentTranscriptStyle(colors: colors)
        let out = NSMutableAttributedString()
        entries.forEach { out.append(style.entry($0)) }
        return out
    }
}
