import AppKit
import CCadex
import Editor
import UniformTypeIdentifiers
import WebKit

/// The rendered note (docs/adr/0010-markdown-rendering.md): the core's HTML
/// in a WKWebView with JavaScript off and a strict content policy. Local
/// images come through the cadex-file: scheme, only from inside the
/// workspace; clicked links go back to the app instead of navigating.
@MainActor
final class MarkdownPreview: NSObject, WKNavigationDelegate {
    let view: WKWebView
    private let path: String
    /// A clicked link: its URL.
    var onLink: ((URL) -> Void)?

    static let scheme = "cadex-file"

    init(path: String) {
        self.path = path
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(LocalFiles(), forURLScheme: Self.scheme)
        view = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
    }

    func show(_ markdown: String) {
        let body = MarkdownIndex.render(markdown)
        view.loadHTMLString(Self.page(body: body, look: EditorAppearance.current), baseURL: Self.url(for: path))
    }

    /// The note's own address: relative links and images resolve against
    /// its folder, `#anchor` stays in the page.
    static func url(for path: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = ""
        parts.path = path
        return parts.url
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else { return decisionHandler(.allow) }
        // A jump to a heading of this same note scrolls the page.
        if url.scheme == Self.scheme, url.path == path, url.fragment != nil { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        onLink?(url)
    }

    static func page(body: String, look: EditorAppearance) -> String {
        // With the alpha: the code background is the foreground at 6 %, and
        // dropping the alpha painted it almost white (2026-10-19).
        func css(_ color: NSColor?) -> String {
            guard let c = color?.usingColorSpace(.sRGB) else { return "inherit" }
            return String(format: "rgba(%d,%d,%d,%.3f)", Int(c.redComponent * 255), Int(c.greenComponent * 255),
                          Int(c.blueComponent * 255), c.alphaComponent)
        }
        let tokens = look.tokens.map { ".t\($0.key) { color: \(css($0.value)); }" }.joined(separator: "\n")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(scheme): data:; style-src 'unsafe-inline'">
        <style>
        body { font: 14px -apple-system, system-ui, sans-serif; line-height: 1.6; color: \(css(look.foreground));
               background: \(css(look.background)); max-width: 860px; margin: 0 auto; padding: 24px 32px; }
        a { color: \(css(look.tokens[16])); } a.wiki { text-decoration-style: dotted; }
        h1, h2 { border-bottom: 1px solid \(css(look.lineNumber)); padding-bottom: .3em; }
        code, pre { font-family: "\(look.font.familyName ?? "Menlo")", ui-monospace, monospace; font-size: 13px; }
        code { background: \(css(look.currentLine)); padding: .1em .35em; border-radius: 4px; }
        pre { background: \(css(look.currentLine)); padding: 12px 14px; border-radius: 6px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        table { border-collapse: collapse; } th, td { border: 1px solid \(css(look.lineNumber)); padding: 4px 10px; }
        blockquote { margin: 0; padding-left: 1em; border-left: 3px solid \(css(look.lineNumber)); opacity: .85; }
        img { max-width: 100%; } li.task { list-style: none; margin-left: -1.3em; }
        \(tokens)
        </style></head><body>\(body)</body></html>
        """
    }
}

/// Serves cadex-file: requests (the note's images) from disk, only inside
/// an authorized folder: the page cannot read anything else.
private final class LocalFiles: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, cadex_workspace_is_authorized(url.path),
              let data = FileManager.default.contents(atPath: url.path) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
