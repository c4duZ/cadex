import AppKit
import Editor
import Strings
import Tabs
import UILooks

/// A file in conflict, in three columns and the result (docs/spec/source-
/// control.md, Conflito em três vias): the common base, ours and theirs
/// above, read-only; the file below, editable, its blocks tinted. Ours,
/// Theirs and Both act on the block under the cursor (else the first);
/// Mark Resolved saves and stages, refused while a marker is left. The bar's
/// buttons only run the commands by id.
@MainActor
public final class ConflictDocument: NSObject, TabDocument, NSTextViewDelegate {
    public let view = NSView()
    public var onChange: (() -> Void)?
    public let repo: String
    public let path: String
    /// The bar's buttons run git.accept-ours and the rest through this.
    public var runCommand: ((String) -> Bool)?
    private let columns = (0..<3).map { _ in NSTextView.scrollableTextView() }
    private let result = NSTextView.scrollableTextView()
    private let status = NSTextField(labelWithString: "")
    private let look = EditorAppearance.current
    private var edited = false

    public init(repo: String, path: String) {
        self.repo = repo
        self.path = path
        super.init()
        build()
        load()
    }

    public static func identity(repo: String, path: String) -> String { "conflict:\(repo)/\(path)" }
    public var identity: String { Self.identity(repo: repo, path: path) }
    public var title: String { (path as NSString).lastPathComponent + T(" (conflict)", " (conflito)") }
    public var hasUnsavedChanges: Bool { edited }
    public func focus() { view.window?.makeFirstResponder(resultText) }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}

    var resultText: NSTextView { result.documentView as! NSTextView }
    var text: String { resultText.string }

    /// The three stages from git and the file from the disk.
    public func load() {
        let git = GitRepository(root: repo)
        let path = self.path
        let full = repo + "/" + path
        git.queue.async { [weak self] in
            let stages = [":1", ":2", ":3"].map { git.blob(rev: $0, path: path).map { String(decoding: $0, as: UTF8.self) } ?? "" }
            let disk = (FileManager.default.contents(atPath: full)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.show(stages, disk) } }
        }
    }

    private func show(_ stages: [String], _ disk: String) {
        for (scroll, stage) in zip(columns, stages) {
            let view = scroll.documentView as! NSTextView
            view.textStorage?.setAttributedString(EditorColoring.attributed(stage, fileName: path))
        }
        resultText.string = disk
        edited = false
        refresh()
    }

    // MARK: Resolving

    func accept(_ side: GitRepository.Side) {
        let blocks = GitRepository.conflictBlocks(text)
        guard !blocks.isEmpty else { return say(T("No conflict left in this file", "Nenhum conflito sobrando neste arquivo")) }
        let line = cursorLine()
        let which = blocks.firstIndex { $0.start <= line && line <= $0.end } ?? 0
        guard let resolved = GitRepository.resolve(text, block: which, side: side) else { return }
        let start = blocks[which].start
        resultText.string = resolved
        edited = true
        moveCursor(toLine: start)
        refresh()
        onChange?()
    }

    public func markResolved() {
        if let line = GitRepository.markerLine(text) {
            moveCursor(toLine: line - 1)
            return say(T("A conflict marker is still on line \(line)", "Ainda há um marcador de conflito na linha \(line)"))
        }
        let git = GitRepository(root: repo)
        let path = self.path
        let text = self.text
        git.queue.async { [weak self] in
            let error = git.markResolved(path: path, text: text)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self else { return }
                if let error { return self.say(error) }
                self.edited = false
                self.say(T("Resolved and staged", "Resolvido e no stage"))
                self.onChange?()
            } }
        }
    }

    public var blocksLeft: Int { GitRepository.conflictBlocks(text).count }

    public func textDidChange(_ notification: Notification) {
        edited = true
        refresh()
        onChange?()
    }

    private func refresh() {
        let blocks = GitRepository.conflictBlocks(text)
        say(blocks.isEmpty ? T("No conflict left: Mark Resolved saves and stages", "Nenhum conflito sobrando: Marcar resolvido grava e faz o stage")
                           : blocks.count == 1 ? T("1 conflict left", "1 conflito sobrando")
                           : T("\(blocks.count) conflicts left", "\(blocks.count) conflitos sobrando"))
        tint(blocks)
    }

    /// Ours blue, the base grey, theirs green, the markers dim.
    private func tint(_ blocks: [GitRepository.ConflictBlock]) {
        guard let storage = resultText.textStorage else { return }
        let ranges = lineRanges()
        storage.beginEditing()
        storage.setAttributes([.font: look.font, .foregroundColor: look.foreground], range: NSRange(location: 0, length: storage.length))
        func paint(_ lines: Range<Int>, _ color: NSColor) {
            for line in lines where ranges.indices.contains(line) { storage.addAttribute(.backgroundColor, value: color, range: ranges[line]) }
        }
        for block in blocks {
            paint(block.ours, NSColor.systemBlue.withAlphaComponent(0.16))
            if let base = block.base { paint(base, NSColor.systemGray.withAlphaComponent(0.16)) }
            paint(block.theirs, NSColor.systemGreen.withAlphaComponent(0.16))
            for marker in [block.start, block.end] + [block.base.map { $0.lowerBound - 1 }, block.theirs.lowerBound - 1].compactMap({ $0 }) where ranges.indices.contains(marker) {
                storage.addAttribute(.foregroundColor, value: look.lineNumber, range: ranges[marker])
            }
        }
        storage.endEditing()
    }

    private func lineRanges() -> [NSRange] {
        var ranges: [NSRange] = []
        let string = text as NSString
        var at = 0
        while at <= string.length {
            let line = string.lineRange(for: NSRange(location: at, length: 0))
            ranges.append(line)
            if NSMaxRange(line) <= at { break }
            at = NSMaxRange(line)
            if at == string.length { break }
        }
        return ranges
    }

    private func cursorLine() -> Int {
        let at = resultText.selectedRange().location
        return lineRanges().firstIndex { NSLocationInRange(at, $0) || NSMaxRange($0) == at } ?? 0
    }

    private func moveCursor(toLine line: Int) {
        let ranges = lineRanges()
        guard ranges.indices.contains(line) else { return }
        resultText.setSelectedRange(NSRange(location: ranges[line].location, length: 0))
        resultText.scrollRangeToVisible(ranges[line])
    }

    func say(_ message: String) { status.stringValue = message }

    private func build() {
        status.font = UILooks.font(11.5)
        status.textColor = .secondaryLabelColor
        let buttons = [("git.accept-ours", T("Ours", "A nossa")), ("git.accept-theirs", T("Theirs", "A deles")),
                       ("git.accept-both", T("Both", "As duas")), ("git.mark-resolved", T("Mark Resolved", "Marcar resolvido"))]
            .map { id, title in CommandButton(title: title) { [weak self] in _ = self?.runCommand?(id) } }
        let bar = NSStackView(views: [status, NSView()] + buttons)
        bar.edgeInsets = NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        let titles = [T("Base", "Base"), T("Ours", "A nossa"), T("Theirs", "A deles")]
        let top = NSStackView(views: zip(columns, titles).map { scroll, title in column(scroll, title) })
        top.distribution = .fillEqually
        top.spacing = 1
        resultText.delegate = self
        resultText.isRichText = false
        resultText.allowsUndo = true
        resultText.font = look.font
        resultText.backgroundColor = look.background
        resultText.textColor = look.foreground
        // A fixed share, not a split view: the split gave the result no
        // height at all (measured in a test window, 2026-11-15).
        let bottom = column(result, T("Result (the file)", "Resultado (o arquivo)"))
        let stack = NSStackView(views: [bar, top, bottom])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor), top.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor), top.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 0.38),
        ])
    }

    private func column(_ scroll: NSScrollView, _ title: String) -> NSView {
        let text = scroll.documentView as! NSTextView
        if scroll !== result {
            text.isEditable = false
            text.backgroundColor = look.background
        }
        scroll.drawsBackground = true
        scroll.backgroundColor = look.background
        let label = NSTextField(labelWithString: title)
        label.font = UILooks.font(11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        // A plain box with the text pinned to its edges: inside a stack in
        // the split, the result came up empty (seen in the app, 2026-11-15).
        let box = NSView()
        for view in [label, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 4), label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 2),
            scroll.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 3), scroll.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: box.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])
        return box
    }
}

/// A button that runs a closure (the command by id).
@MainActor
final class CommandButton: NSButton {
    var onPress: (() -> Void)? {
        get { run }
        set { run = newValue }
    }
    private var run: (() -> Void)?

    convenience init(title: String, run: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.run = run
        target = self
        action = #selector(pressed)
        bezelStyle = .rounded
        controlSize = .small
    }

    @objc private func pressed() { run?() }
}
