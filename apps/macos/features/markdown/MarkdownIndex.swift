import Foundation
import CCadex

/// The core's Markdown index of the workspace (cadex_markdown_*): notes,
/// headings, the links of an unsaved text, backlinks, where a link goes.
@MainActor
final class MarkdownIndex {
    struct Heading: Equatable {
        let level: Int
        let line: Int
        let anchor: String
        let text: String
    }

    struct Link: Equatable {
        /// UTF-16 range in the text that was checked.
        let range: NSRange
        let kind: Int
        let broken: Bool
        /// Absolute path, or empty (web links, outside the workspace).
        let target: String
        /// Line of the heading named, 0 if none.
        let line: Int
        var isWeb: Bool { kind == 2 }
    }

    /// Read by deinit, which is not on the main actor; closing is safe from
    /// any thread in the core.
    nonisolated(unsafe) private var handle: OpaquePointer?
    private(set) var root: String

    init(root: String) {
        self.root = root
        open(root)
    }

    deinit {
        cadex_markdown_index_close(handle)
    }

    func open(_ path: String) {
        cadex_markdown_index_close(handle)
        handle = nil
        root = path
        var out: OpaquePointer?
        if cadex_markdown_index_open(path, &out) == CADEX_OK { handle = out }
    }

    /// The first read of the workspace is done.
    var isReady: Bool { cadex_markdown_index_ready(handle) }

    /// Relative paths of every note.
    func notes() -> [String] {
        lines { cadex_markdown_notes(handle, &$0, &$1) }.map { $0[0] }
    }

    func headings(of path: String) -> [Heading] {
        lines { cadex_markdown_headings(handle, path, &$0, &$1) }.compactMap { f in
            guard f.count >= 4, let level = Int(f[0]), let line = Int(f[1]) else { return nil }
            return Heading(level: level, line: line, anchor: f[2], text: f[3])
        }
    }

    /// The links of `text`, the unsaved content of the note at `path`.
    func links(in text: String, of path: String) -> [Link] {
        let bytes = Array(text.utf8)
        return lines { out, len in
            bytes.withUnsafeBufferPointer { cadex_markdown_links(handle, path, $0.baseAddress, $0.count, &out, &len) }
        }.compactMap { f in
            guard f.count >= 6, let start = Int(f[0]), let end = Int(f[1]), let kind = Int(f[2]) else { return nil }
            return Link(range: NSRange(location: start, length: end - start), kind: kind, broken: f[3] == "1",
                        target: f[4], line: Int(f[5]) ?? 0)
        }
    }

    /// Notes linking to `path`: (absolute path, line).
    func backlinks(to path: String) -> [(path: String, line: Int)] {
        lines { cadex_markdown_backlinks(handle, path, &$0, &$1) }.compactMap { f in
            guard f.count >= 2, let line = Int(f[1]) else { return nil }
            return (f[0], line)
        }
    }

    /// Where `destination`, written in the note at `path`, goes.
    func resolve(_ destination: String, from path: String, wiki: Bool) -> (path: String, line: Int)? {
        let f = lines { cadex_markdown_resolve(handle, path, destination, wiki, &$0, &$1) }.first ?? []
        guard f.count >= 2, let line = Int(f[1]) else { return nil }
        return (f[0], line)
    }

    /// Rendered HTML for a Markdown text.
    static func render(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        let status = bytes.withUnsafeBufferPointer { cadex_markdown_render($0.baseAddress, $0.count, &out, &len) }
        guard status == CADEX_OK, let out else { return "" }
        defer { cadex_free(out) }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }

    /// Runs a call that hands back tab-separated lines and splits them.
    private func lines(_ call: (inout UnsafeMutablePointer<UInt8>?, inout Int) -> cadex_status) -> [[String]] {
        guard handle != nil else { return [] }
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        guard call(&out, &len) == CADEX_OK, let out else { return [] }
        defer { cadex_free(out) }
        let text = String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
        return text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }
}
