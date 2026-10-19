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
    private(set) var codeView: CodeTextView?
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

    /// The text view, for features that work on the text (markdown).
    public var textView: NSTextView? { codeView }
    /// ⌘+click on the character at an offset; true when handled.
    public var commandClick: ((Int) -> Bool)? {
        get { codeView?.commandClick }
        set { codeView?.commandClick = newValue }
    }
    /// What shows instead of the text (the rendered Markdown), or nil.
    public private(set) var alternate: NSView?
    /// A control another feature puts at the top right of the tab, over the
    /// text and over the alternate view alike (markdown's "Visualizar").
    public var accessory: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            placeAccessory()
        }
    }
    private var textContainer: NSView?

    /// Shows `view` in place of the text, or the text again with nil.
    public func showAlternate(_ view: NSView?) {
        alternate = view
        guard let content = view ?? textContainer else { return }
        place(content)
        if view == nil { focus() }
    }

    public var title: String { (path as NSString).lastPathComponent }
    public var identity: String { path }
    /// "Zig", or nil for plain text.
    public var language: String? { highlighter?.language }

    public func focus() {
        if let codeView { view.window?.makeFirstResponder(codeView) }
    }

    public func close() {
        if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
        codeView?.textStorage?.delegate = nil
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
        let (scroll, codeView) = makeTextView()
        loading = true
        codeView.string = text
        loading = false
        codeView.isEditable = !readOnly
        codeView.indentUnit = CodeTextView.detectIndent(text)
        let highlighter = EditorHighlighter(storage: codeView.textStorage!, fileName: path, appearance: EditorAppearance.current,
                                            highlight: text.utf8.count <= EditorFile.maxHighlightBytes)
        highlighter.onTextChange = { [weak self] in self?.textChanged() }
        self.highlighter = highlighter
        self.codeView = codeView
        folding.lines = highlighter.lines
        folding.setRegions(highlighter.folds())
        applyAppearance()
        textContainer = scroll
        place(scroll)
    }

    private func makeTextView() -> (NSScrollView, CodeTextView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let codeView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        codeView.autoresizingMask = [.width]
        codeView.isRichText = false
        codeView.allowsUndo = true
        codeView.usesFindBar = true
        codeView.isIncrementalSearchingEnabled = true
        codeView.isAutomaticQuoteSubstitutionEnabled = false
        codeView.isAutomaticDashSubstitutionEnabled = false
        codeView.isAutomaticTextReplacementEnabled = false
        codeView.isAutomaticSpellingCorrectionEnabled = false
        codeView.isContinuousSpellCheckingEnabled = false
        codeView.smartInsertDeleteEnabled = false
        codeView.textContainerInset = NSSize(width: 4, height: 6)
        codeView.textContainer?.widthTracksTextView = true
        (codeView.textLayoutManager?.textContentManager as? NSTextContentStorage)?.delegate = folding
        scroll.documentView = codeView
        let ruler = LineRuler(textView: codeView, scrollView: scroll)
        ruler.folding = folding
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        self.ruler = ruler
        folding.onChange = { [weak self] in self?.foldsChanged() }
        return (scroll, codeView)
    }

    private func placeAccessory() {
        guard let accessory else { return }
        accessory.removeFromSuperview()
        accessory.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(accessory, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            accessory.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 8),
            // Clear of the vertical scroller.
            accessory.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
        ])
    }

    private func place(_ content: NSView) {
        view.subviews.filter { $0 !== banner && $0 !== accessory }.forEach { $0.removeFromSuperview() }
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
        placeAccessory()
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
        guard let codeView, let layout = codeView.textLayoutManager else { return }
        layout.invalidateLayout(for: layout.documentRange)
        codeView.needsLayout = true
        codeView.needsDisplay = true
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
        guard let codeView else { return }
        loading = true
        codeView.string = text
        loading = false
        highlighter?.paintAll()
    }

    func applyAppearance() {
        let look = EditorAppearance.current
        guard let codeView, let highlighter else { return }
        highlighter.appearance = look
        codeView.backgroundColor = look.background
        codeView.insertionPointColor = look.foreground
        codeView.currentLineColor = look.currentLine
        codeView.selectedTextAttributes = [.backgroundColor: look.selection]
        codeView.typingAttributes = [.font: look.font, .foregroundColor: look.foreground]
        ruler?.background = look.background
        ruler?.numberColor = look.lineNumber
        ruler?.font = .monospacedDigitSystemFont(ofSize: max(look.font.pointSize - 2, 9), weight: .regular)
        highlighter.paintAll()
    }
}
