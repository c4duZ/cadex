import CCadex

/// Markdown into HTML by the core (sanitized there), from any thread: the page
/// of a Markdown file shared to the phone (plan 39 E) shows it rendered.
public enum MarkdownHTML {
    public static func render(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        let status = bytes.withUnsafeBufferPointer { cadex_markdown_render($0.baseAddress, $0.count, &out, &len) }
        guard status == CADEX_OK, let out else { return "" }
        defer { cadex_free(out) }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }
}
