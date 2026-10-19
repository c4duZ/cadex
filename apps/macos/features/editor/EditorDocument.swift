import AppKit
import Tabs

/// A file open in an editor tab (docs/spec/editor.md): the text view with
/// line numbers, folds and colors, saving through the core, and following
/// the file when it changes on disk.
@MainActor
public final class EditorDocument: TabDocument {
    public let path: String
    public let view = NSView()
    public var onChange: (() -> Void)?
    public private(set) var hasUnsavedChanges = false {
        didSet { if hasUnsavedChanges != oldValue { onChange?() } }
    }
    let banner = EditorBanner()
    private(set) var textView: CodeTextView?
    private var ruler: LineRuler?
    private(set) var highlighter: EditorHighlighter?
    let folding = EditorFolding()
    private(set) var readOnly = false
    /// What was last read from or written to disk, to tell our own saves
    /// and unchanged files from real changes.
    private var diskData: Data?
    private var appearanceObserver: NSObjectProtocol?
    /// Set while the text is replaced by a load, so it does not count as an edit.
    private var loading = false
    /// A non-text file: the app opens it in the system's default app.
    public var openExternally: ((String) -> Void)?

    public init(path: String) {
        self.path = path
        view.addSubview(banner)
        load()
        appearanceObserver = NotificationCenter.default.addObserver(forName: EditorAppearance.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
    }

    public var title: String { (path as NSString).lastPathComponent }
    public var identity: String { path }
    /// "Zig", or nil for plain text.
    public var language: String? { highlighter?.language }

    public func focus() {
        if let textView { view.window?.makeFirstResponder(textView) }
    }

    public func close() {
        if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
        textView?.textStorage?.delegate = nil
    }

    // MARK: Loading

    private func load() {
        switch EditorFile.read(path) {
        case let .text(text, data, truncated, valid):
            diskData = data
            readOnly = truncated || !valid
            showText(text)
            if truncated {
                banner.show("Arquivo grande: mostrando os primeiros 10 MB, só para leitura.")
            } else if !valid {
                banner.show("O arquivo não é UTF-8 válido: aberto só para leitura.")
            } else if data.count > EditorFile.maxHighlightBytes {
                banner.show("Arquivo acima de 1 MB: sem cores nem dobras.")
            }
        case .binary:
            showMessage("Arquivo binário", action: "Abrir no app padrão")
        case let .failed(message):
            showMessage(message, action: nil)
        }
    }

    private func showText(_ text: String) {
        let (scroll, textView) = makeTextView()
        loading = true
        textView.string = text
        loading = false
        textView.isEditable = !readOnly
        textView.indentUnit = CodeTextView.detectIndent(text)
        let highlighter = EditorHighlighter(storage: textView.textStorage!, fileName: path, appearance: EditorAppearance.current,
                                            highlight: text.utf8.count <= EditorFile.maxHighlightBytes)
        highlighter.onTextChange = { [weak self] in self?.textChanged() }
        self.highlighter = highlighter
        self.textView = textView
        folding.lines = highlighter.lines
        folding.setRegions(highlighter.folds())
        applyAppearance()
        place(scroll)
    }

    private func makeTextView() -> (NSScrollView, CodeTextView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textContainer?.widthTracksTextView = true
        (textView.textLayoutManager?.textContentManager as? NSTextContentStorage)?.delegate = folding
        scroll.documentView = textView
        let ruler = LineRuler(textView: textView, scrollView: scroll)
        ruler.folding = folding
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        self.ruler = ruler
        folding.onChange = { [weak self] in self?.foldsChanged() }
        return (scroll, textView)
    }

    private func place(_ content: NSView) {
        view.subviews.filter { $0 !== banner }.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: banner.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func showMessage(_ text: String, action: String?) {
        let message = EditorMessageView(text: text, action: action) { [weak self] in
            guard let self else { return }
            self.openExternally?(self.path)
        }
        place(message)
    }

    // MARK: Changes

    private func textChanged() {
        guard let highlighter else { return }
        folding.lines = highlighter.lines
        // Line numbers moved under the folds: open them rather than hide
        // the wrong lines.
        folding.unfoldAll()
        folding.setRegions(highlighter.folds())
        ruler?.updateThickness()
        ruler?.needsDisplay = true
        if !loading { hasUnsavedChanges = true }
    }

    private func foldsChanged() {
        guard let textView, let layout = textView.textLayoutManager else { return }
        layout.invalidateLayout(for: layout.documentRange)
        textView.needsLayout = true
        textView.needsDisplay = true
        ruler?.needsDisplay = true
    }

    var diskDataForComparison: Data? { diskData }

    /// The text matches what is on disk (`data`).
    func markSaved(_ data: Data, clean: Bool = true) {
        diskData = data
        if clean { hasUnsavedChanges = false }
    }

    /// Replaces the whole text without counting it as an edit.
    func replaceAllText(_ text: String) {
        guard let textView else { return }
        loading = true
        textView.string = text
        loading = false
        highlighter?.paintAll()
    }

    func applyAppearance() {
        let look = EditorAppearance.current
        guard let textView, let highlighter else { return }
        highlighter.appearance = look
        textView.backgroundColor = look.background
        textView.insertionPointColor = look.foreground
        textView.currentLineColor = look.currentLine
        textView.selectedTextAttributes = [.backgroundColor: look.selection]
        textView.typingAttributes = [.font: look.font, .foregroundColor: look.foreground]
        ruler?.background = look.background
        ruler?.numberColor = look.lineNumber
        ruler?.font = .monospacedDigitSystemFont(ofSize: max(look.font.pointSize - 2, 9), weight: .regular)
        highlighter.paintAll()
    }
}
