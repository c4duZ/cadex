import Foundation

/// The page around a shared file (plan 39 E), as the phone's Safari shows it:
/// the name, the size, Download, and the file itself when Safari can show
/// it in a page (a picture, a video, a PDF, an HTML page, Markdown rendered,
/// text); Word, Excel and PowerPoint open by Safari's own preview (Open).
public enum FileSharePage {
    public enum Kind: Equatable { case html, image, video, audio, pdf, office, markdown, text, other }

    public static func kind(of path: String) -> Kind {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return .html
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg": return .image
        case "mp4", "mov", "m4v", "webm": return .video
        case "mp3", "m4a", "wav", "aac": return .audio
        case "pdf": return .pdf
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "rtf": return .office
        case "md", "markdown": return .markdown
        case "txt", "log", "csv", "json", "yaml", "yml", "toml", "xml", "swift", "zig", "rs", "py", "js", "ts", "tsx",
             "jsx", "go", "c", "h", "cpp", "java", "rb", "sh", "css", "sql": return .text
        default: return .other
        }
    }

    /// The media type a file is served with (Safari previews Office files by it).
    public static func mime(of path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "mp3": return "audio/mpeg"
        case "m4a", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "rtf": return "application/rtf"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        default:
            return kind(of: path) == .text || kind(of: path) == .markdown ? "text/plain; charset=utf-8" : "application/octet-stream"
        }
    }

    /// The page for `share`; `markdown` turns Markdown into HTML (the markdown
    /// feature's, given by the app).
    public static func page(_ share: FileShareStore.Share, size: Int64, markdown: ((String) -> String)?) -> String {
        let name = escape(share.name)
        let raw = "raw/" + (share.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? share.name)
        let body: String
        switch kind(of: share.path) {
        case .html: body = #"<iframe src="\#(raw)"></iframe>"#
        case .image: body = #"<img src="\#(raw)" alt="\#(name)">"#
        case .video: body = #"<video src="\#(raw)" controls playsinline></video>"#
        case .audio: body = #"<audio src="\#(raw)" controls></audio>"#
        case .pdf: body = #"<iframe src="\#(raw)"></iframe>"#
        case .markdown:
            let text = (try? String(contentsOfFile: share.path, encoding: .utf8)) ?? ""
            body = #"<article>\#(markdown?(text) ?? "<pre>" + escape(text) + "</pre>")</article>"#
        case .text:
            let text = (try? String(contentsOfFile: share.path, encoding: .utf8)) ?? ""
            body = "<pre>" + escape(String(text.prefix(2_000_000))) + "</pre>"
        case .office, .other: body = ""
        }
        let open = kind(of: share.path) == .markdown || kind(of: share.path) == .text ? "" : #"<a href="\#(raw)">Open</a>"#
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(name)</title><style>\(style)</style></head><body>
        <header><div><b>\(name)</b><small>\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))</small></div>
        <nav>\(open)<a href="download">Download</a></nav></header>
        <main>\(body)</main></body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The page's own look, light and dark with the system; no fonts or scripts from outside.
    static let style = """
    :root{color-scheme:light dark;--bg:#fff;--fg:#1d1d1f;--muted:#6e6e73;--line:#d2d2d7;--accent:#0a66d8}
    @media (prefers-color-scheme:dark){:root{--bg:#141518;--fg:#f2f2f4;--muted:#9a9aa1;--line:#2c2d31;--accent:#5aa2ff}}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 -apple-system,system-ui,sans-serif}
    header{position:sticky;top:0;display:flex;gap:12px;align-items:center;justify-content:space-between;padding:12px 16px;
    background:var(--bg);border-bottom:1px solid var(--line)}header div{min-width:0;display:flex;flex-direction:column}
    header b{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}small{color:var(--muted)}
    nav{display:flex;gap:16px;flex-shrink:0}nav a{color:var(--accent);text-decoration:none;font-weight:600}
    main{padding:16px}img,video{max-width:100%;height:auto;display:block;margin:0 auto}audio{width:100%}
    iframe{width:100%;height:calc(100vh - 110px);border:1px solid var(--line);border-radius:8px;background:#fff}
    pre{white-space:pre-wrap;word-break:break-word;font:13px/1.45 ui-monospace,Menlo,monospace}
    article{max-width:720px;margin:0 auto}article img{max-width:100%}
    """
}
