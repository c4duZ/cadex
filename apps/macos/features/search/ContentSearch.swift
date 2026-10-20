import AppKit
import Strings
import CCadex
import CommandPalette
import Icons

/// ⌘⇧F: text in the workspace's files (docs/spec/search.md). Each keystroke
/// cancels the search running in the core and starts another; results come
/// in batches from the core's thread and are shown as they arrive.
@MainActor
public final class ContentSearch: PaletteSource {
    /// The options the toggle commands change.
    var caseSensitive = false
    var regex = false
    var showHidden = true
    private(set) var root = ""
    /// Read by deinit, which is not on the main actor; cancelling is safe
    /// from any thread in the core.
    nonisolated(unsafe) private var running: OpaquePointer?
    private var box: Box?
    private var hits: [Hit] = []
    private var show: (@MainActor ([PaletteItem], String?) -> Void)?
    let open: (String, Int?, Bool?) -> Void

    struct Hit: Equatable, Sendable {
        let path: String
        let line: Int
        let text: String
        /// UTF-8 offsets of the match inside `text`.
        let matchStart: Int
        let matchLength: Int
    }

    init(open: @escaping (String, Int?, Bool?) -> Void) {
        self.open = open
    }

    func setRoot(_ path: String, showHidden: Bool) {
        stop()
        root = path
        self.showHidden = showHidden
    }

    public var placeholder: String { T("Find text in files", "Buscar texto nos arquivos") }
    public var emptyText: String { T("No results", "Nenhum resultado") }
    public var icon: Icon { .magnifyingGlass }
    public var hints: [PaletteHint] {
        [PaletteHint("↩", T("open", "abrir")), PaletteHint("⌥↩", T("to the side", "ao lado")), PaletteHint("⌘↩", T("in new tab", "em nova aba"))]
    }

    public func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        stop()
        hits = []
        self.show = show
        guard !query.isEmpty else { return show([], labeled(nil)) }
        var options = cadex_search_content_options(case_sensitive: caseSensitive, regex: regex, show_hidden: showHidden, max_results: 0)
        let box = Box(owner: self)
        self.box = box
        var callbacks = cadex_search_content_callbacks(
            context: Unmanaged.passUnretained(box).toOpaque(), on_hits: contentSearchHits, on_done: contentSearchDone)
        var out: OpaquePointer?
        let bytes = Array(query.utf8)
        let status = bytes.withUnsafeBufferPointer {
            cadex_search_content_start(root, $0.baseAddress, $0.count, &options, &callbacks, &out)
        }
        guard status == CADEX_OK else {
            return show([], labeled(status == CADEX_INVALID_ARGUMENT && regex ? T("Invalid regular expression", "Expressão regular inválida") : T("The search failed", "A busca falhou")))
        }
        running = out
        show([], labeled(T("Searching…", "Buscando…")))
    }

    public func choose(_ item: PaletteItem) {
        choose(item, as: .primary)
    }

    public func choose(_ item: PaletteItem, as choice: PaletteChoice) {
        guard let index = Int(item.id), index < hits.count else { return }
        let hit = hits[index]
        open(FileSearchPaths.absolute(hit.path, in: root), hit.line, choice == .primary ? nil : choice == .option)
    }

    /// Cancels the core's search: no batch of it is delivered afterwards,
    /// and batches already queued to the main thread find a dead box.
    public func stop() {
        cadex_search_content_cancel(running)
        running = nil
        box?.owner = nil
        box = nil
    }

    deinit {
        cadex_search_content_cancel(running)
    }

    /// A batch from the core, on the main thread.
    fileprivate func received(_ batch: [Hit]) {
        hits += batch
        show?(items(), labeled(T("\(hits.count) results", "\(hits.count) resultados")))
    }

    fileprivate func finished(truncated: Bool, files: Int) {
        let summary = truncated ? T("Too many results, refine the search", "Resultados demais, refine a busca") : T("\(hits.count) results in \(files) files", "\(hits.count) resultados em \(files) arquivos")
        show?(items(), labeled(summary))
    }

    /// The status with the options in effect in front: "Aa .* · 12 resultados".
    func labeled(_ status: String?) -> String? {
        let options = [caseSensitive ? "Aa" : nil, regex ? ".*" : nil].compactMap { $0 }.joined(separator: " ")
        let parts = [options.isEmpty ? nil : options, status].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func items() -> [PaletteItem] {
        hits.enumerated().map { i, hit in
            let offsets = Array(hit.matchStart..<(hit.matchStart + hit.matchLength))
            return PaletteItem(id: String(i), title: hit.text,
                               bold: PaletteItem.boldRanges(in: hit.text, byteOffsets: offsets),
                               detail: "\(hit.path):\(hit.line)",
                               image: FileIcons.image(forFileNamed: (hit.path as NSString).lastPathComponent))
        }
    }

    /// Carries the batches from the core's thread; `owner` is cleared when
    /// the search is cancelled, so late batches are dropped.
    fileprivate final class Box: @unchecked Sendable {
        @MainActor weak var owner: ContentSearch?
        init(owner: ContentSearch) { self.owner = owner }
    }
}

/// The core calls these on its search thread: plain functions, not closures
/// of the main-actor class (see FileWatcher.swift in the explorer).
private func contentSearchHits(context: UnsafeMutableRawPointer?, hits: UnsafePointer<cadex_search_hit>?, count: Int) {
    guard let context, let hits else { return }
    let box = Unmanaged<ContentSearch.Box>.fromOpaque(context).takeUnretainedValue()
    let batch = (0..<count).map { i -> ContentSearch.Hit in
        let h = hits[i]
        let bytes = UnsafeBufferPointer(start: h.text, count: Int(h.text_len))
        return ContentSearch.Hit(path: String(cString: h.path), line: Int(h.line),
                                 text: String(decoding: bytes, as: UTF8.self),
                                 matchStart: Int(h.match_start), matchLength: Int(h.match_len))
    }
    // Retained by the block, so the box outlives a cancel racing with it.
    let retained = Unmanaged.passRetained(box)
    DispatchQueue.main.async {
        MainActor.assumeIsolated { retained.takeUnretainedValue().owner?.received(batch) }
        retained.release()
    }
}

private func contentSearchDone(context: UnsafeMutableRawPointer?, truncated: Bool, files: UInt32) {
    guard let context else { return }
    let box = Unmanaged<ContentSearch.Box>.fromOpaque(context).takeUnretainedValue()
    let retained = Unmanaged.passRetained(box)
    DispatchQueue.main.async {
        MainActor.assumeIsolated { retained.takeUnretainedValue().owner?.finished(truncated: truncated, files: Int(files)) }
        retained.release()
    }
}
