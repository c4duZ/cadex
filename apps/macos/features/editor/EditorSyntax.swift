import Foundation
import CCadex

/// The core's syntax tree for one open file (cadex_editor_*): colored spans
/// and fold regions, in UTF-16 units so they are NSRanges as they come.
@MainActor
final class EditorSyntax {
    struct Span: Equatable {
        let range: NSRange
        let kind: UInt8
    }

    struct Fold: Equatable {
        /// 0-based lines; `end` is the last line inside the fold.
        let start: Int
        let end: Int
    }

    /// Read by deinit, which is not on the main actor; closing is safe from
    /// any thread in the core.
    nonisolated(unsafe) private var handle: OpaquePointer?
    /// "Zig", or nil for plain text.
    let language: String?

    init(fileName: String, text: String) {
        var out: OpaquePointer?
        let units = Array(text.utf16)
        _ = units.withUnsafeBytes { cadex_editor_open(fileName, $0.baseAddress, $0.count, UInt8(CADEX_TEXT_UTF16), &out) }
        handle = out
        language = cadex_editor_language(out).map { String(cString: $0) }
    }

    deinit {
        cadex_editor_close(handle)
    }

    /// The text in `range` (old text) became `replacement`. Returns the
    /// range of the new text whose colors may have changed.
    func edit(_ range: NSRange, replacement: String) -> NSRange {
        let units = Array(replacement.utf16)
        var lo: UInt32 = 0
        var hi: UInt32 = 0
        let status = units.withUnsafeBytes {
            cadex_editor_edit(handle, UInt32(range.location), UInt32(NSMaxRange(range)), $0.baseAddress, $0.count, &lo, &hi)
        }
        guard status == CADEX_OK else { return NSRange(location: range.location, length: units.count) }
        return NSRange(location: Int(lo), length: Int(hi) - Int(lo))
    }

    func spans(in range: NSRange) -> [Span] {
        var out: UnsafeMutablePointer<cadex_editor_span>?
        var count = 0
        guard cadex_editor_highlights(handle, UInt32(range.location), UInt32(NSMaxRange(range)), &out, &count) == CADEX_OK,
              let out else { return [] }
        defer { cadex_free(out) }
        return (0..<count).map {
            let s = out[$0]
            return Span(range: NSRange(location: Int(s.start), length: Int(s.end - s.start)), kind: s.kind)
        }
    }

    func folds() -> [Fold] {
        var out: UnsafeMutablePointer<cadex_editor_fold>?
        var count = 0
        guard cadex_editor_folds(handle, &out, &count) == CADEX_OK, let out else { return [] }
        defer { cadex_free(out) }
        return (0..<count).map { Fold(start: Int(out[$0].start_row), end: Int(out[$0].end_row)) }
    }
}
