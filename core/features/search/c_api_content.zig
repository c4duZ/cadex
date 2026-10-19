//! Content search (⌘⇧F) in the C API (include/cadex.h).

const std = @import("std");
const status = @import("../../status.zig");
const workspace = @import("../workspace/workspace.zig");
const content = @import("content.zig");

pub const Options = extern struct {
    case_sensitive: bool,
    regex: bool,
    show_hidden: bool,
    /// 0: 2000.
    max_results: u32,
};

/// Starts a search on its own thread; results come through `callbacks`.
/// An invalid regex is CADEX_INVALID_ARGUMENT, before any thread starts.
pub export fn cadex_search_content_start(
    root: ?[*:0]const u8,
    query: ?[*]const u8,
    query_len: usize,
    options: ?*const Options,
    callbacks: ?*const content.Callbacks,
    out: ?*?*content.Search,
) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    result.* = null;
    const p = std.mem.span(root orelse return status.invalid_argument);
    if (query_len == 0) return status.invalid_argument;
    const q = (query orelse return status.invalid_argument)[0..query_len];
    const o = options orelse return status.invalid_argument;
    const cb = callbacks orelse return status.invalid_argument;
    var opts: content.Options = .{ .case_sensitive = o.case_sensitive, .regex = o.regex, .show_hidden = o.show_hidden };
    if (o.max_results > 0) opts.max_results = o.max_results;
    result.* = content.Search.start(std.heap.c_allocator, workspace.registry(), p, q, opts, cb.*) catch |err|
        return status.fromError(err);
    return status.ok;
}

/// Stops the search and frees it; no callback runs after this returns.
/// Must not be called from inside a callback. NULL is accepted.
pub export fn cadex_search_content_cancel(search: ?*content.Search) callconv(.c) void {
    if (search) |s| s.cancel();
}

test "an invalid regex is refused through the C API" {
    _ = try workspace.registry().authorize("/usr/share");
    const options: Options = .{ .case_sensitive = false, .regex = true, .show_hidden = false, .max_results = 0 };
    const callbacks: content.Callbacks = .{};
    var search: ?*content.Search = null;
    try std.testing.expectEqual(status.invalid_argument, cadex_search_content_start("/usr/share", "(", 1, &options, &callbacks, &search));
    try std.testing.expect(search == null);
}
