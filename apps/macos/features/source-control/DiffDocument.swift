import AppKit
import Editor
import Tabs

/// A file's diff in a tab (docs/spec/source-control.md, "Diff"): before and
/// after side by side with the editor's colors, removed lines red on the
/// left and added ones green on the right, scrolling together; or the
/// patch in one column. Binary and huge files say so instead.
@MainActor
public final class DiffDocument: TabDocument {
    public let view = NSView()
    public var onChange: (() -> Void)?
    public let request: SourceControlController.DiffRequest
    private var diff: GitRepository.Diff?
    private(set) var sideBySide = true
    private var left: NSTextView?
    private var right: NSTextView?
    private var syncing = false
    private var openTarget: OpenFileTarget?
    private var scrollObservers: [NSObjectProtocol] = []
    /// "Abrir o arquivo" for files too big for the diff.
    public var openFile: ((String) -> Void)?

    public init(request: SourceControlController.DiffRequest) {
        self.request = request
        load()
    }

    public static func identity(for request: SourceControlController.DiffRequest) -> String {
        let side = request.commit.map { "commit \($0)" } ?? (request.staged ? "staged" : "work")
        return "diff:\(side):\(request.repo)/\(request.path)"
    }

    public var identity: String { Self.identity(for: request) }
    public var title: String {
        let side = request.commit.map { " (\($0.prefix(7)))" } ?? (request.staged ? " (staged)" : " (diff)")
        return (request.path as NSString).lastPathComponent + side
    }
    public var hasUnsavedChanges: Bool { false }
    public func focus() { view.window?.makeFirstResponder(left ?? right) }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}

    /// Reads the diff again (the file changed on disk).
    public func load() {
        let repo = GitRepository(root: request.repo)
        let request = self.request
        repo.queue.async { [weak self] in
            let diff = if let sha = request.commit {
                repo.diff(commit: sha, path: request.path, orig: request.orig)
            } else {
                repo.diff(path: request.path, orig: request.orig, staged: request.staged)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.show(diff) } }
        }
    }

    /// diff.toggle-layout: side by side or the patch.
    public func toggleLayout() {
        sideBySide.toggle()
        show(diff)
    }

    private func show(_ diff: GitRepository.Diff?) {
        self.diff = diff
        guard let diff else { return place(message("Não foi possível ler o diff")) }
        if diff.binary { return place(message("Arquivo binário, sem diff")) }
        if diff.tooLarge { return place(message("Arquivo grande demais para o diff", action: "Abrir o arquivo")) }
        sideBySide ? showSides(diff) : showPatch(diff)
        onChange?()
    }

    private func showSides(_ diff: GitRepository.Diff) {
        let lines = DiffLines(patch: diff.patch)
        let (leftScroll, leftText) = textView(diff.before, marked: lines.removed, color: .systemRed)
        let (rightScroll, rightText) = textView(diff.after, marked: lines.added, color: .systemGreen)
        left = leftText
        right = rightText
        // Two equal columns: a split view placed its divider before it had a
        // width and hid the left side (2026-10-19).
        let columns = NSStackView(views: [leftScroll, rightScroll])
        columns.distribution = .fillEqually
        columns.spacing = 1
        place(columns)
        // Observers run on the main queue, where the views live.
        let pair = [leftScroll, rightScroll]
        for scroll in pair {
            scroll.contentView.postsBoundsChangedNotifications = true
            let clip = scroll.contentView
            scrollObservers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow(clip, in: pair) }
            })
        }
    }

    /// One side scrolled: the other goes to the same place, in proportion.
    private func follow(_ moved: NSClipView?, in scrolls: [NSScrollView]) {
        guard !syncing, let moved, let source = scrolls.first(where: { $0.contentView === moved }),
              let target = scrolls.first(where: { $0 !== source }) else { return }
        syncing = true
        defer { syncing = false }
        let sourceHeight = max((source.documentView?.frame.height ?? 1) - moved.bounds.height, 1)
        let targetHeight = max((target.documentView?.frame.height ?? 1) - target.contentView.bounds.height, 0)
        let y = moved.bounds.origin.y / sourceHeight * targetHeight
        target.contentView.scroll(to: NSPoint(x: target.contentView.bounds.origin.x, y: y))
        target.reflectScrolledClipView(target.contentView)
    }

    private func showPatch(_ diff: GitRepository.Diff) {
        let look = EditorAppearance.current
        let text = NSMutableAttributedString(string: diff.patch.isEmpty ? "Sem diferenças" : diff.patch,
                                             attributes: [.font: look.font, .foregroundColor: look.foreground])
        var at = 0
        for line in diff.patch.components(separatedBy: "\n") {
            let length = (line as NSString).length
            let color: NSColor? = line.hasPrefix("+") ? .systemGreen : line.hasPrefix("-") ? .systemRed : line.hasPrefix("@@") ? .systemBlue : nil
            if let color, at + length <= text.length { text.addAttribute(.foregroundColor, value: color, range: NSRange(location: at, length: length)) }
            at += length + 1
        }
        let (scroll, textView) = textView(attributed: text)
        left = textView
        right = nil
        place(scroll)
    }

    private func textView(_ text: String, marked: Set<Int>, color: NSColor) -> (NSScrollView, NSTextView) {
        let colored = NSMutableAttributedString(attributedString: EditorColoring.attributed(text, fileName: request.path))
        var line = 1
        var at = 0
        for piece in text.components(separatedBy: "\n") {
            let length = (piece as NSString).length
            if marked.contains(line), at + length <= colored.length {
                colored.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.18), range: NSRange(location: at, length: max(length, 0)))
            }
            at += length + 1
            line += 1
        }
        return textView(attributed: colored)
    }

    private func textView(attributed: NSAttributedString) -> (NSScrollView, NSTextView) {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = EditorAppearance.current.background
        textView.textStorage?.setAttributedString(attributed)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        scroll.drawsBackground = true
        scroll.backgroundColor = EditorAppearance.current.background
        return (scroll, textView)
    }

    private func message(_ text: String, action: String? = nil) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        var views: [NSView] = [label]
        if let action {
            let target = OpenFileTarget { [weak self] in
                guard let self else { return }
                self.openFile?(self.request.repo + "/" + self.request.path)
            }
            openTarget = target
            views.append(NSButton(title: action, target: target, action: #selector(OpenFileTarget.open(_:))))
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func place(_ content: NSView) {
        scrollObservers.forEach(NotificationCenter.default.removeObserver)
        scrollObservers = []
        view.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

/// The "Abrir o arquivo" button needs an Objective-C target.
private final class OpenFileTarget: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func open(_ sender: Any?) { handler() }
}
