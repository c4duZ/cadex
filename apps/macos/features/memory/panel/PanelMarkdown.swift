import AppKit
import Strings
import UILooks

/// A memory page's Markdown drawn natively (plan 40 D). The repository keeps WebView out of the
/// interface (ADR 0001; the markdown feature's WebKit preview is for a note open in the editor), so
/// the page is an attributed text: the lines read as the project page's memory reads them
/// (MemoryPageText, plan 34: headings, items, paragraphs, the title heading left to the page's
/// title) plus code fences, and each line's inline marks (**bold**, *italic*, `code`, links) parsed
/// by Foundation, as the agents' replies are (AgentMarkdown). A link to another page of the memory
/// (`[x](decisions/a.md)`, `[[decisions/a]]`) opens it in the panel; a web link, the browser.
@MainActor
enum PanelMarkdown {
    /// A heading of the page, for "Nesta página".
    struct Heading: Equatable {
        var level: Int
        var text: String
    }

    /// The scheme of a link to a memory page in the drawn text.
    static let pageScheme = "cadex-memory-page"

    static func render(_ markdown: String) -> (text: NSAttributedString, headings: [Heading]) {
        typealias M = MP.Markdown
        let body = UILooks.font(M.fontSize)
        let bold = UILooks.font(M.fontSize, weight: DesignTokens.FontWeight.semibold)
        let mono = UILooks.monospaced(MP.Mono.fontSize)
        let out = NSMutableAttributedString()
        var headings: [Heading] = []
        var fence = false
        var paragraph: [String] = []
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = M.lineHeight
        style.paragraphSpacing = UILooks.pt(M.gap)
        let item = style.mutableCopy() as! NSMutableParagraphStyle
        item.headIndent = UILooks.pt(M.fontSize + M.gap)
        item.paragraphSpacing = UILooks.pt(MP.Chip.gap)

        func add(_ text: NSAttributedString) {
            if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(text)
        }
        func flush() {
            guard !paragraph.isEmpty else { return }
            add(inline(paragraph.joined(separator: " "), font: body, bold: bold, mono: mono, style: style))
            paragraph = []
        }
        for raw in MemoryPageText.body(markdown).components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flush()
                fence.toggle()
                continue
            }
            if fence {
                add(NSAttributedString(string: raw, attributes: [.font: mono, .foregroundColor: DesignTokens.Color.textSecondary]))
                continue
            }
            if line.isEmpty { flush(); continue }
            if let level = headingLevel(line) {
                flush()
                let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                // The title heading is the page's title, drawn above (MemoryPageText leaves it too).
                guard level > 1 else { continue }
                headings.append(Heading(level: level, text: text))
                let size = level == 2 ? DesignTokens.FontSize.sheetTitle : M.fontSize
                add(NSAttributedString(string: MemoryPageText.plain(text), attributes: [
                    .font: UILooks.font(size, weight: DesignTokens.FontWeight.semibold), .foregroundColor: DesignTokens.Color.textPrimary,
                    .paragraphStyle: style,
                ]))
            } else if let marker = itemMarker(line) {
                flush()
                let text = NSMutableAttributedString(string: "•\t", attributes: [.font: body, .foregroundColor: MP.Head.meta, .paragraphStyle: item])
                text.append(inline(String(line.dropFirst(marker)), font: body, bold: bold, mono: mono, style: item))
                add(text)
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return (out, headings)
    }

    static func headingLevel(_ line: String) -> Int? {
        let level = line.prefix { $0 == "#" }.count
        return level > 0 && level <= 6 && line.dropFirst(level).first == " " ? level : nil
    }

    /// The length of "- ", "* " or "1. " before an item's words.
    static func itemMarker(_ line: String) -> Int? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return 2 }
        guard let match = line.range(of: #"^\d+\. "#, options: .regularExpression) else { return nil }
        return line.distance(from: line.startIndex, to: match.upperBound)
    }

    /// One line's inline Markdown; a page link becomes a `cadex-memory-page:` link.
    static func inline(_ line: String, font: NSFont, bold: NSFont, mono: NSFont, style: NSParagraphStyle) -> NSAttributedString {
        let wiki = line.replacingOccurrences(of: #"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#, with: "[$1](wiki:$1)", options: .regularExpression)
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: MP.Markdown.color, .paragraphStyle: style]
        guard let parsed = try? AttributedString(markdown: wiki, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: line, attributes: plain)
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes = plain
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { attributes[.font] = bold }
            if intent.contains(.emphasized) { attributes[.font] = NSFontManager.shared.convert(attributes[.font] as? NSFont ?? font, toHaveTrait: .italicFontMask) }
            if intent.contains(.code) {
                attributes[.font] = mono
                attributes[.foregroundColor] = DesignTokens.Color.textSecondary
            }
            if let link = run.link {
                attributes[.link] = target(link)
                attributes[.foregroundColor] = MP.Link.color
            }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return out
    }

    /// A link as the page opens it: web links as they are, the rest a page path of the memory.
    static func target(_ link: URL) -> URL {
        if let scheme = link.scheme, ["http", "https", "mailto"].contains(scheme) { return link }
        var path = link.scheme == "wiki" ? String(link.absoluteString.dropFirst("wiki:".count)) : link.relativeString
        path = path.removingPercentEncoding ?? path
        if let hash = path.firstIndex(of: "#") { path = String(path[..<hash]) }
        while path.hasPrefix("./") || path.hasPrefix("/") { path.removeFirst(path.hasPrefix("./") ? 2 : 1) }
        if !path.hasSuffix(".md") { path += ".md" }
        return URL(string: pageScheme + ":" + PanelPath.page(path)) ?? link
    }

    /// The page path of a `cadex-memory-page:` link; nil for another link.
    static func pagePath(_ url: URL) -> String? {
        guard url.scheme == pageScheme else { return nil }
        let rest = String(url.absoluteString.dropFirst(pageScheme.count + 1))
        return rest.removingPercentEncoding ?? rest
    }
}

/// The drawn Markdown: a read-only, selectable text as tall as its lines at the column's width; a
/// page link calls `openPage`, a web link opens in the browser.
@MainActor
final class PanelTextView: NSTextView, NSTextViewDelegate {
    private let openPage: (String) -> Void

    init(_ text: NSAttributedString, openPage: @escaping (String) -> Void) {
        self.openPage = openPage
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        textContainerInset = .zero
        linkTextAttributes = [.foregroundColor: MP.Link.color, .cursor: NSCursor.pointingHand]
        delegate = self
        setContentHuggingPriority(.required, for: .vertical)
        setAccessibilityLabel(T("Page text", "Texto da página"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelTextView is created in code") }

    override init(frame: NSRect, textContainer: NSTextContainer?) { fatalError("PanelTextView is created with its text") }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(layoutManager.usedRect(for: textContainer).height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
        if let path = PanelMarkdown.pagePath(url) {
            openPage(path)
            return true
        }
        NSWorkspace.shared.open(url)
        return true
    }

    /// For tests: a page link followed.
    func follow(_ url: URL) { _ = textView(self, clickedOnLink: url, at: 0) }
}
