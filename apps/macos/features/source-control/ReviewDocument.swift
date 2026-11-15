import AppKit
import Editor
import Strings
import Tabs
import UILooks

/// A worktree's review in a tab (docs/spec/review.md): every change since
/// the base, the files listed on the left and stacked on the right, read
/// off the main thread; j/k and n/p move between files and changes, and
/// hunks or marked lines go in and out of the index.
@MainActor
public final class ReviewDocument: TabDocument {
    /// What to review: a worktree against a base (nil: the task's start
    /// branch, else the default branch), or two tips against each other.
    public struct Request: Equatable, Sendable {
        public var repo: String
        public var start: String?
        public var base: String?
        public var to: String?
        public init(repo: String, start: String? = nil, base: String? = nil, to: String? = nil) {
            self.repo = repo
            self.start = start
            self.base = base
            self.to = to
        }
    }

    public let view = NSView()
    public var onChange: (() -> Void)?
    public private(set) var request: Request
    public var openFile: ((String) -> Void)?
    /// A file in conflict: the app opens it in three columns (repo, path).
    public var onOpenConflict: ((String, String) -> Void)?
    /// Notes under lines (the review feature's comments), set by the app.
    public var annotations: [ReviewAnnotation] = [] { didSet { if annotations != oldValue { relayout() } } }
    /// A read finished (the app places the comments again), a note was
    /// clicked (its id), lines were asked a comment ("+" in the margin).
    public var onLoaded: (() -> Void)?
    public var onAnnotation: ((String) -> Void)?
    public var onCommentRequest: ((ReviewLineSelection) -> Void)?
    /// A button on the bar ("Send to Agent (2)"), running what the app gives.
    public var barAction: (title: String, run: () -> Void)? { didSet { showBarAction() } }
    let barButton = CommandButton(title: "") {}
    /// A setting changed from the tab (context, wrap, whitespace): the app saves it.
    public var onSetting: ((Int, Bool, Bool) -> Void)?
    let text = ReviewTextView()
    let tree = ReviewTree()
    let bar = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let repo: GitRepository
    var files: [ReviewFileDiff] = []
    var options = ReviewLayout.Options()
    private(set) var base: String?
    private var loading = false
    /// What the last action said, shown before the summary after the next read.
    var notice: String?
    private var again = false

    public init(request: Request, context: Int = 3, wrap: Bool = false, whitespace: Bool = false) {
        self.request = request
        repo = GitRepository(root: request.repo)
        options.context = context
        text.wrap = wrap
        text.showWhitespace = whitespace
        build()
        load()
    }

    public static func identity(for request: Request) -> String {
        "review:\(request.repo)" + (request.to.map { "…\($0)" } ?? "")
    }

    public var identity: String { Self.identity(for: request) }
    public var title: String {
        let name = (request.repo as NSString).lastPathComponent
        return request.to.map { T("Compare \(request.base ?? "") ↔ \($0)", "Comparar \(request.base ?? "") ↔ \($0)") } ?? T("Review · \(name)", "Revisão · \(name)")
    }
    public var hasUnsavedChanges: Bool { false }
    public var isFocused: Bool { view.window?.firstResponder === text }
    /// Back on the tab: read again, since a worktree outside the workspace
    /// sends no disk events.
    public func focus() {
        view.window?.makeFirstResponder(text)
        loadSoon()
    }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}

    // MARK: Reading

    private static var pending: Set<ObjectIdentifier> = []

    /// The disk changed: read again in a moment, once for a burst of saves
    /// (an agent writing files).
    public func loadSoon() {
        let key = ObjectIdentifier(self)
        guard !Self.pending.contains(key) else { return }
        Self.pending.insert(key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                Self.pending.remove(key)
                self?.load()
            }
        }
    }

    /// Reads everything again (the disk changed, a stage, a new base).
    public func load() {
        guard !loading else { again = true; return }
        loading = true
        let repo = self.repo
        let request = self.request
        repo.queue.async { [weak self] in
            let base = request.base ?? repo.reviewBase(start: request.start)
            let files = base.flatMap { repo.reviewFiles(base: $0, to: request.to) } ?? []
            let diffs = files.prefix(500).map { file in
                var diff = ReviewFileDiff(file: file, diff: base.flatMap { repo.reviewDiff(base: $0, to: request.to, path: file.path, orig: file.orig) })
                if diff.binary, ImageDiffView.isImage(file.path), let base { Self.readImages(&diff, repo: repo, base: base, to: request.to) }
                return diff
            }
            let exists = FileManager.default.fileExists(atPath: request.repo)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.loaded(base: base, files: diffs, exists: exists) } }
        }
    }

    private func loaded(base: String?, files: [ReviewFileDiff], exists: Bool) {
        loading = false
        self.base = base
        self.files = files
        tree.show(files.map(\.file))
        relayout()
        let added = files.compactMap(\.file.added).reduce(0, +)
        let removed = files.compactMap(\.file.removed).reduce(0, +)
        let shown = base.map { String($0.prefix(7)) } ?? "—"
        let origin = request.base == nil ? (request.start.map { " (\($0))" } ?? "") : ""
        defer { notice = nil }
        if !exists {
            say(T("This task's worktree no longer exists", "A worktree desta tarefa não existe mais"))
        } else if base == nil {
            say(T("No base to compare with: choose one (Set Review Base)", "Sem base para comparar: escolha uma (Trocar a base da revisão)"))
        } else if files.isEmpty {
            say(T("Nothing changed since \(shown)\(origin)", "Nada mudou desde \(shown)\(origin)"))
        } else {
            say(T("Base \(shown)\(origin) · \(files.count) files · +\(added) −\(removed)",
                  "Base \(shown)\(origin) · \(files.count) arquivos · +\(added) −\(removed)"))
        }
        onLoaded?()
        if again { again = false; load() }
    }

    /// An image's two versions: the base's, and the disk's (or the other tip's).
    nonisolated static func readImages(_ diff: inout ReviewFileDiff, repo: GitRepository, base: String, to: String?) {
        let file = diff.file
        diff.beforeData = file.isNew ? nil : repo.blob(rev: base, path: file.orig.isEmpty ? file.path : file.orig)
        diff.afterData = file.status == "D" ? nil : (to.map { repo.blob(rev: $0, path: file.path) }
            ?? FileManager.default.contents(atPath: repo.root + "/" + file.path))
    }

    /// git.review-image-mode: every image of the tab, together.
    public func cycleImageMode() { text.imageMode = text.imageMode.next }
    public var hasImages: Bool { text.layout.rows.contains { if case .image = $0 { return true } else { return false } } }

    func relayout() {
        let layout = ReviewLayout(files: files, options: options, annotations: annotations) { diff in
            // Short: the note is one line (the long one was cut, 2026-11-15).
            if diff.file.status == "U" { return T("Merge conflict · right-click it on the left: Resolve Conflict",
                                                    "Conflito de merge · clique direito nele à esquerda: Resolver o conflito") }
            // An image too big to compare: its sizes, and Open File on the left (plan 21 phase C).
            if diff.beforeData != nil || diff.afterData != nil {
                let sizes = [ImageDiffView.describe(T("before", "antes"), diff.beforeData, nil), ImageDiffView.describe(T("after", "depois"), diff.afterData, nil)]
                return T("Image too large to compare (\(sizes.joined(separator: ", "))) · right-click it on the left: Open File",
                         "Imagem grande demais para comparar (\(sizes.joined(separator: ", "))) · clique direito à esquerda: Abrir o arquivo")
            }
            if diff.binary { return T("Binary file", "Arquivo binário") }
            if diff.tooLarge { return T("File too large to diff", "Arquivo grande demais para o diff") }
            // No hunk: a rename or a mode change, with the same content.
            return diff.patch.contains("\n@@") || diff.patch.hasPrefix("@@") ? nil : T("Only the name or the mode changed", "Só o nome ou o modo mudou")
        }
        text.show(layout, files: files)
    }

    func say(_ message: String) {
        bar.stringValue = notice.map { "\($0) — \(message)" } ?? message
    }

    // MARK: Moving (j/k, n/p)

    public func nextFile() { jump(in: text.layout.fileStarts, forward: true) }
    public func previousFile() { jump(in: text.layout.fileStarts, forward: false) }
    public func nextChange() { jump(in: text.layout.changeStarts, forward: true) }
    public func previousChange() { jump(in: text.layout.changeStarts, forward: false) }

    private func jump(in starts: [Int], forward: Bool) {
        let target = forward ? starts.first { $0 > text.cursor } : starts.last { $0 < text.cursor }
        if let target { text.go(to: target) }
    }

    // MARK: Showing

    public func toggleCollapse() {
        options.showAll.toggle()
        relayout()
    }

    public func toggleWrap() {
        text.wrap.toggle()
        onSetting?(options.context, text.wrap, text.showWhitespace)
    }

    public func toggleWhitespace() {
        text.showWhitespace.toggle()
        onSetting?(options.context, text.wrap, text.showWhitespace)
    }

    /// git.review-set-base: any commit or branch.
    public func setBase(_ base: String) {
        request.base = base.isEmpty ? nil : base
        onChange?()
        load()
    }

    private func openFold(_ file: Int, _ region: Int) {
        options.opened.insert("\(file):\(region)")
        relayout()
    }

    private func build() {
        bar.font = UILooks.font(11.5)
        bar.textColor = .secondaryLabelColor
        bar.lineBreakMode = .byTruncatingTail
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = text.look.background
        text.autoresizingMask = [.width]
        text.onOpenFold = { [weak self] file, region in self?.openFold(file, region) }
        text.onCursor = { [weak self] row in
            guard let self, text.layout.rows.indices.contains(row) else { return }
            tree.follow(ReviewLayout.file(of: text.layout.rows[row]))
        }
        tree.onPick = { [weak self] file in
            guard let self, text.layout.fileStarts.indices.contains(file) else { return }
            text.go(to: text.layout.fileStarts[file])
        }
        tree.onResolve = { [weak self] file in
            guard let self, files.indices.contains(file) else { return }
            onOpenConflict?(request.repo, files[file].file.path)
        }
        tree.onOpenFile = { [weak self] file in
            guard let self, files.indices.contains(file) else { return }
            openFile?(request.repo + "/" + files[file].file.path)
        }
        text.onAnnotation = { [weak self] id in self?.onAnnotation?(id) }
        text.onComment = { [weak self] rows in
            guard let self, let selection = selection(of: Array(rows)) else { return }
            onCommentRequest?(selection)
        }
        barButton.isHidden = true
        let top = NSStackView(views: [bar, NSView(), barButton])
        top.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        let body = NSSplitView()
        body.isVertical = true
        body.dividerStyle = .thin
        body.addArrangedSubview(tree.scroll)
        body.addArrangedSubview(scroll)
        tree.scroll.widthAnchor.constraint(equalToConstant: UILooks.pt(250)).isActive = true
        let column = NSStackView(views: [top, body])
        column.orientation = .vertical
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: view.topAnchor), column.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor), column.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            top.widthAnchor.constraint(equalTo: column.widthAnchor), body.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }
}
