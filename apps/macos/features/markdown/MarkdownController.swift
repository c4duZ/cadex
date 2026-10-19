import AppKit
import CommandPalette
import Editor

/// Entry point of the markdown feature (docs/spec/markdown.md): the index of
/// the workspace's notes, the help attached to each note open in the
/// editor, the rendered view, and "who points here".
@MainActor
public final class MarkdownController {
    let index: MarkdownIndex
    var root: String { index.root }
    /// File search of the workspace, for `](` suggestions: relative paths.
    private let findFiles: (String) -> [String]
    /// Opens a file in the app, at a 1-based line when known.
    private let open: (String, Int?) -> Void
    private var sessions: [ObjectIdentifier: MarkdownSession] = [:]

    public init(root: String, findFiles: @escaping (String) -> [String], open: @escaping (String, Int?) -> Void) {
        index = MarkdownIndex(root: root)
        self.findFiles = findFiles
        self.open = open
    }

    public static func isMarkdown(_ path: String) -> Bool {
        ["md", "markdown"].contains((path as NSString).pathExtension.lowercased())
    }

    public func setRoot(_ root: String) {
        if root != index.root { index.open(root) }
    }

    /// Adds the Markdown help to a note open in the editor.
    public func attach(_ document: EditorDocument) {
        guard Self.isMarkdown(document.path), document.textView != nil else { return }
        sessions[ObjectIdentifier(document)] = MarkdownSession(document: document, controller: self)
        refreshWhenReady()
    }

    /// Links checked before the index's first read finished look broken
    /// or unknown: check again once it is ready.
    private func refreshWhenReady() {
        guard !index.isReady else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if self.index.isReady {
                self.sessions.values.forEach { $0.refreshLinks() }
            } else {
                self.refreshWhenReady()
            }
        }
    }

    func session(for document: EditorDocument) -> MarkdownSession? {
        sessions[ObjectIdentifier(document)]
    }

    /// markdown.toggle-preview: text and rendered page, in the same tab.
    /// Back to the text, the page goes (WebKit's memory with it); the next
    /// toggle renders a new one.
    public func togglePreview(_ document: EditorDocument) {
        if document.alternate != nil {
            document.showAlternate(nil)
            return
        }
        let preview = MarkdownPreview(path: document.path)
        preview.onLink = { [weak self, weak document] url in
            guard let self, let document else { return }
            self.followRendered(url, from: document.path)
        }
        preview.show(document.textView?.string ?? "")
        document.showAlternate(preview.handOff())
    }

    /// markdown.open-link: the link under the cursor.
    public func openLink(in document: EditorDocument) {
        guard let session = sessions[ObjectIdentifier(document)], let cursor = document.textView?.selectedRange().location else { return }
        session.follow(at: cursor)
    }

    /// The notes linking to `path`, as a palette list (markdown.backlinks).
    public func backlinks(of path: String) -> PaletteSource {
        BacklinksSource(path: path, root: root, items: index.backlinks(to: path), open: open)
    }

    // MARK: Following links

    func follow(_ link: MarkdownIndex.Link) {
        if link.isWeb {
            if let url = URL(string: link.target) { NSWorkspace.shared.open(url) }
            return
        }
        guard !link.target.isEmpty, !link.broken || FileManager.default.fileExists(atPath: link.target) else { return NSSound.beep() }
        open(link.target, link.line > 0 ? link.line : nil)
    }

    /// A link clicked in the rendered page.
    private func followRendered(_ url: URL, from path: String) {
        switch url.scheme {
        case "cadex-wiki":
            let name = url.absoluteString.dropFirst("cadex-wiki:".count).removingPercentEncoding ?? ""
            if let target = index.resolve(name, from: path, wiki: true) { open(target.path, target.line > 0 ? target.line : nil) }
        case MarkdownPreview.scheme:
            var line: Int?
            if let fragment = url.fragment, Self.isMarkdown(url.path) {
                line = index.headings(of: url.path).first { $0.anchor.caseInsensitiveCompare(fragment) == .orderedSame }?.line
            }
            open(url.path, line)
        default:
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Suggestions

    func suggestions(for trigger: CompletionTrigger, from note: String) -> [CompletionPopup.Item] {
        switch trigger {
        case let .path(query, _):
            return findFiles(query).prefix(30).map {
                CompletionPopup.Item(title: ($0 as NSString).lastPathComponent, detail: $0,
                                     insert: CompletionTrigger.relativePath(to: $0, from: note))
            }
        case let .heading(file, query, _):
            let target = file.isEmpty ? note : (Self.normalize((note as NSString).deletingLastPathComponent + "/" + file))
            return index.headings(of: root + "/" + target)
                .filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.anchor.contains(query.lowercased()) }
                .map { CompletionPopup.Item(title: $0.text, detail: "#" + $0.anchor, insert: $0.anchor) }
        case let .note(query, _):
            return index.notes()
                .filter { query.isEmpty || ($0 as NSString).lastPathComponent.localizedCaseInsensitiveContains(query) }
                .prefix(30)
                .map { CompletionPopup.Item(title: (($0 as NSString).lastPathComponent as NSString).deletingPathExtension,
                                            detail: $0, insert: (($0 as NSString).lastPathComponent as NSString).deletingPathExtension + "]]") }
        }
    }

    /// `a/./b/../c.md` -> `a/c.md`, relative to the root.
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for p in path.split(separator: "/") {
            if p == "." || p.isEmpty { continue }
            if p == ".." { _ = parts.popLast() } else { parts.append(p) }
        }
        return parts.joined(separator: "/")
    }
}

/// "Quem aponta pra cá" in the palette: each note linking here, at the line.
@MainActor
private final class BacklinksSource: PaletteSource {
    let items: [PaletteItem]
    let open: (String, Int?) -> Void

    init(path: String, root: String, items list: [(path: String, line: Int)], open: @escaping (String, Int?) -> Void) {
        self.open = open
        items = list.map { entry in
            let rel = entry.path.hasPrefix(root + "/") ? String(entry.path.dropFirst(root.count + 1)) : entry.path
            return PaletteItem(id: "\(entry.path)\t\(entry.line)", title: rel, detail: "linha \(entry.line)")
        }
    }

    var placeholder: String { "Quem aponta para esta nota" }
    var emptyText: String { "Nenhuma nota aponta para esta" }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let shown = query.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(query) }
        show(shown, "\(items.count) links")
    }

    func choose(_ item: PaletteItem) {
        let parts = item.id.split(separator: "\t")
        guard parts.count == 2 else { return }
        open(String(parts[0]), Int(parts[1]))
    }

    func stop() {}
}
