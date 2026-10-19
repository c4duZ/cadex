//! The explorer feature's part of the C API (include/cadex.h): listing,
//! reading and changing files. Watching is in c_api_watch.zig.

const std = @import("std");
const status = @import("../../status.zig");
const workspace = @import("../workspace/workspace.zig");
const explorer = @import("explorer.zig");
const c_buffer = @import("../../shared/c_buffer.zig");

const paths = workspace.paths;
/// Buffers handed to the app come from malloc, freed with cadex_free or
/// cadex_explorer_listing_free.
const gpa = std.heap.c_allocator;

pub const Entry = extern struct {
    /// Into Listing.names; UTF-8, not NUL-terminated.
    name_offset: u32,
    name_len: u32,
    /// explorer.listing.Kind: 0 file, 1 folder, 2 symbolic link, 3 other.
    kind: u8,
    link_to_directory: bool,
    /// Left out by .gitignore, .ignore or .git/info/exclude.
    ignored: bool,
    size: u64,
};

pub const Listing = extern struct {
    entries: ?[*]Entry,
    count: usize,
    names: ?[*]u8,
};

fn span(path: ?[*:0]const u8) ?[]const u8 {
    return std.mem.span(path orelse return null);
}

/// Lists a folder: folders first, natural order, `.git` left out.
pub export fn cadex_explorer_list(path: ?[*:0]const u8, out: ?*Listing) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    result.* = .{ .entries = null, .count = 0, .names = null };
    const p = span(path) orelse return status.invalid_argument;
    var listing = explorer.listing.list(gpa, workspace.registry(), p) catch |err| return status.fromError(err);
    defer listing.deinit();
    return flatten(listing.entries, result);
}

fn flatten(entries: []const explorer.listing.Entry, result: *Listing) status.Code {
    var total: usize = 0;
    for (entries) |e| total += e.name.len;
    // malloc(0) may return NULL: keep at least one slot of each.
    const flat = gpa.alloc(Entry, @max(entries.len, 1)) catch return status.out_of_memory;
    const names = gpa.alloc(u8, @max(total, 1)) catch {
        gpa.free(flat);
        return status.out_of_memory;
    };
    var at: usize = 0;
    for (entries, flat[0..entries.len]) |e, *f| {
        f.* = .{
            .name_offset = @intCast(at),
            .name_len = @intCast(e.name.len),
            .kind = @intFromEnum(e.kind),
            .link_to_directory = e.link_to_directory,
            .ignored = e.ignored,
            .size = e.size,
        };
        @memcpy(names[at..][0..e.name.len], e.name);
        at += e.name.len;
    }
    result.* = .{ .entries = flat.ptr, .count = entries.len, .names = names.ptr };
    return status.ok;
}

pub export fn cadex_explorer_listing_free(listing: ?*Listing) callconv(.c) void {
    const l = listing orelse return;
    std.c.free(l.entries);
    std.c.free(l.names);
    l.* = .{ .entries = null, .count = 0, .names = null };
}

pub export fn cadex_explorer_create_file(path: ?[*:0]const u8) callconv(.c) status.Code {
    const p = span(path) orelse return status.invalid_argument;
    explorer.operations.createFile(workspace.registry(), p) catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_explorer_create_directory(path: ?[*:0]const u8) callconv(.c) status.Code {
    const p = span(path) orelse return status.invalid_argument;
    explorer.operations.createDirectory(workspace.registry(), p) catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_explorer_rename(path: ?[*:0]const u8, new_name: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const p = span(path) orelse return status.invalid_argument;
    const name = span(new_name) orelse return status.invalid_argument;
    var buf: paths.Buffer = undefined;
    const to = explorer.operations.rename(workspace.registry(), p, name, &buf) catch |err| return status.fromError(err);
    return c_buffer.handOut(to, out, out_len);
}

pub export fn cadex_explorer_move(path: ?[*:0]const u8, destination: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const p = span(path) orelse return status.invalid_argument;
    const dest = span(destination) orelse return status.invalid_argument;
    var buf: paths.Buffer = undefined;
    const to = explorer.operations.move(workspace.registry(), p, dest, &buf) catch |err| return status.fromError(err);
    return c_buffer.handOut(to, out, out_len);
}

pub export fn cadex_explorer_copy(path: ?[*:0]const u8, destination: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const p = span(path) orelse return status.invalid_argument;
    const dest = span(destination) orelse return status.invalid_argument;
    var buf: paths.Buffer = undefined;
    const to = explorer.operations.copy(workspace.registry(), p, dest, &buf) catch |err| return status.fromError(err);
    return c_buffer.handOut(to, out, out_len);
}

/// A text file's bytes. `max_size` 0: the viewers' default (10 MB).
pub export fn cadex_explorer_read_text(path: ?[*:0]const u8, max_size: u64, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const p = span(path) orelse return status.invalid_argument;
    if (out == null) return status.invalid_argument;
    const limit = if (max_size == 0) explorer.read.max_text_size else max_size;
    const bytes = explorer.read.readText(gpa, workspace.registry(), p, limit) catch |err| return status.fromError(err);
    defer gpa.free(bytes);
    return c_buffer.handOut(bytes, out, out_len);
}

/// At most `max_size` bytes from the start (0: 10 MB); *truncated tells if
/// the file is longer. CADEX_BINARY as above.
pub export fn cadex_explorer_read_text_head(path: ?[*:0]const u8, max_size: u64, out: ?*?[*]u8, out_len: ?*usize, truncated: ?*bool) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const p = span(path) orelse return status.invalid_argument;
    if (out == null) return status.invalid_argument;
    const limit = if (max_size == 0) explorer.read.max_text_size else max_size;
    const head = explorer.read.readHead(gpa, workspace.registry(), p, limit) catch |err| return status.fromError(err);
    defer gpa.free(head.bytes);
    if (truncated) |t| t.* = head.truncated;
    return c_buffer.handOut(head.bytes, out, out_len);
}

/// Saves `len` bytes over the file (or creates it), atomically.
pub export fn cadex_explorer_write_text(path: ?[*:0]const u8, data: ?[*]const u8, len: usize) callconv(.c) status.Code {
    const p = span(path) orelse return status.invalid_argument;
    const bytes: []const u8 = if (len == 0) "" else (data orelse return status.invalid_argument)[0..len];
    explorer.write.writeText(workspace.registry(), p, bytes) catch |err| return status.fromError(err);
    return status.ok;
}

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

test "lists, creates, renames and reads through the C API" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("folder");
    try dir.writeFile("b.txt", "bee");
    _ = try workspace.registry().authorize(dir.path());

    try testing.expectEqual(status.ok, cadex_explorer_create_file(try dir.join("a.txt")));
    try testing.expectEqual(status.already_exists, cadex_explorer_create_file(try dir.join("a.txt")));
    var listing: Listing = undefined;
    try testing.expectEqual(status.ok, cadex_explorer_list((try dir.join("")).ptr, &listing));
    defer cadex_explorer_listing_free(&listing);
    try testing.expectEqual(@as(usize, 3), listing.count);
    const first = listing.entries.?[0];
    try testing.expectEqualStrings("folder", listing.names.?[first.name_offset..][0..first.name_len]);
    try testing.expectEqual(@as(u8, 1), first.kind);

    var out: ?[*]u8 = null;
    var len: usize = 0;
    try testing.expectEqual(status.ok, cadex_explorer_rename(try dir.join("b.txt"), "c.txt", &out, &len));
    try testing.expect(std.mem.endsWith(u8, out.?[0..len], "/c.txt"));
    std.c.free(out);
    try testing.expectEqual(status.ok, cadex_explorer_read_text(try dir.join("c.txt"), 0, &out, &len));
    try testing.expectEqualStrings("bee", out.?[0..len]);
    std.c.free(out);
    try testing.expectEqual(status.too_large, cadex_explorer_read_text(try dir.join("c.txt"), 2, &out, &len));
    try testing.expectEqual(status.not_authorized, cadex_explorer_create_file("/private/tmp/cadex-outside.txt"));
}
