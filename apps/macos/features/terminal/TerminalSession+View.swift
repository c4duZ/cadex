import CCadex
import Foundation

/// What the view does to a session besides typing: find, links, paste,
/// scrolling, selection, and the mouse for programs (c_api_view.zig).
extension TerminalSession {
    // MARK: Find

    /// Starts finding text in the screen and history; empty stops.
    func searchStart(_ needle: String) {
        guard let handle else { return }
        let bytes = Array(needle.utf8)
        _ = bytes.withUnsafeBufferPointer { cadex_terminal_search_start(handle, $0.baseAddress, $0.count) }
    }

    func searchStop() {
        guard let handle else { return }
        cadex_terminal_search_stop(handle)
    }

    /// Moves the current match: forward toward older matches (Enter).
    func searchSelect(forward: Bool) {
        guard let handle else { return }
        let direction = UInt8(forward ? CADEX_SEARCH_NEXT : CADEX_SEARCH_PREVIOUS)
        _ = cadex_terminal_search_select(handle, direction, nil)
    }

    /// Matches found, and the current one counting from 1 (0: none).
    func searchCounts() -> (total: Int, current: Int) {
        guard let handle else { return (0, 0) }
        var total: UInt32 = 0
        var current: UInt32 = 0
        _ = cadex_terminal_search_counts(handle, &total, &current)
        return (Int(total), Int(current))
    }

    // MARK: Links

    struct Link: Equatable {
        enum Kind { case url, path }
        var kind: Kind
        /// The URL, or the absolute path of an existing file.
        var target: String
        /// First and last cell on screen, row-major.
        var start: (col: Int, row: Int)
        var end: (col: Int, row: Int)

        static func == (a: Link, b: Link) -> Bool {
            a.kind == b.kind && a.target == b.target && a.start == b.start && a.end == b.end
        }
    }

    /// The link at a viewport cell. Refreshes the frame: call it outside
    /// draw, and do not keep a frame pointer across it.
    func link(atCol col: Int, row: Int) -> Link? {
        guard let handle else { return nil }
        var info = cadex_terminal_link()
        var target: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard cadex_terminal_link_at(handle, UInt16(clamping: col), UInt16(clamping: row), &info, &target, &length) == CADEX_OK,
              let target
        else { return nil }
        defer { cadex_free(target) }
        let text = String(decoding: UnsafeBufferPointer(start: target, count: length), as: UTF8.self)
        let kind: Link.Kind = info.kind == UInt8(CADEX_LINK_PATH) ? .path : .url
        return Link(kind: kind, target: text,
                    start: (Int(info.start_col), Int(info.start_row)), end: (Int(info.end_col), Int(info.end_row)))
    }

    // MARK: Paste

    /// Pastes text, encoded by the core for the program (bracketed paste).
    func paste(_ text: String) {
        guard let handle, !text.isEmpty else { return }
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBufferPointer { cadex_terminal_paste(handle, $0.baseAddress, $0.count) }
    }

    /// False when pasting could run commands unseen (several lines into a
    /// shell without bracketed paste).
    func isPasteSafe(_ text: String) -> Bool {
        guard let handle else { return true }
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBufferPointer { cadex_terminal_paste_is_safe(handle, $0.baseAddress, $0.count) }
    }

    /// Paths escaped for the shell and joined by spaces.
    static func quotePaths(_ paths: [String]) -> String {
        var cStrings = paths.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var out: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                cadex_terminal_quote_paths($0, buffer.count, &out, &length)
            }
        }
        guard status == CADEX_OK, let out else { return "" }
        defer { cadex_free(out) }
        return String(decoding: UnsafeBufferPointer(start: out, count: length), as: UTF8.self)
    }

    // MARK: Scrolling and selection

    /// Moves the view through the history; negative goes up.
    func scroll(rows: Int32) {
        guard let handle, rows != 0 else { return }
        _ = cadex_terminal_scroll(handle, rows)
    }

    func scrollToTop() {
        guard let handle else { return }
        _ = cadex_terminal_scroll_to(handle, UInt8(CADEX_SCROLL_TOP))
    }

    func scrollToBottom() {
        guard let handle else { return }
        _ = cadex_terminal_scroll_to(handle, UInt8(CADEX_SCROLL_BOTTOM))
    }

    func selectPress(_ pointer: cadex_terminal_pointer, clicks: Int, extend: Bool) {
        guard let handle else { return }
        var p = pointer
        _ = cadex_terminal_select_press(handle, &p, UInt8(clamping: clicks), extend)
    }

    /// Returns the autoscroll direction: -1 up, 1 down, 0 none.
    func selectDrag(_ pointer: cadex_terminal_pointer) -> Int8 {
        guard let handle else { return 0 }
        var p = pointer
        var autoscroll: Int8 = 0
        _ = cadex_terminal_select_drag(handle, &p, &autoscroll)
        return autoscroll
    }

    func selectAutoscroll(_ pointer: cadex_terminal_pointer) -> Int8 {
        guard let handle else { return 0 }
        var p = pointer
        var autoscroll: Int8 = 0
        _ = cadex_terminal_select_autoscroll(handle, &p, &autoscroll)
        return autoscroll
    }

    func selectRelease(_ pointer: cadex_terminal_pointer) {
        guard let handle else { return }
        var p = pointer
        _ = cadex_terminal_select_release(handle, &p)
    }

    func selectAll() {
        guard let handle else { return }
        _ = cadex_terminal_select_all(handle)
    }

    var hasSelection: Bool {
        guard let handle else { return false }
        return cadex_terminal_has_selection(handle)
    }

    /// The selected text, or nil without a selection.
    func selectedText() -> String? {
        guard let handle else { return nil }
        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard cadex_terminal_copy_selection(handle, &bytes, &length) == CADEX_OK, let bytes else { return nil }
        defer { cadex_free(bytes) }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    }

    // MARK: Mouse for programs, wheel and focus

    /// What the running program asked to receive (CADEX_MOUSE_TRACKING_*).
    var mouseTracking: UInt8 {
        guard let handle else { return 0 }
        return cadex_terminal_mouse_tracking(handle)
    }

    func mouse(_ event: cadex_terminal_mouse_event) {
        guard let handle else { return }
        var e = event
        _ = cadex_terminal_mouse(handle, &e)
    }

    /// Wheel steps: to the program, as arrows on the alternate screen, or
    /// scrolling the history; the core decides.
    func wheel(_ event: cadex_terminal_mouse_event, rows: Int32) {
        guard let handle, rows != 0 else { return }
        var e = event
        _ = cadex_terminal_wheel(handle, &e, rows)
    }

    func focus(_ focused: Bool) {
        guard let handle else { return }
        _ = cadex_terminal_focus(handle, focused)
    }
}
