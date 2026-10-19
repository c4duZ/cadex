//! Text search in the workspace's files, for ⌘⇧F (docs/spec/search.md). One
//! search runs on its own thread and hands results over in batches; a new
//! query cancels the old one, and cancel() returns only after the last
//! callback, so results of an old search never arrive later.

const std = @import("std");
const fs = @import("../../shared/fs.zig");
const workspace = @import("../workspace/workspace.zig");
const Walker = @import("walker.zig").Walker;
const Matcher = @import("content_match.zig").Matcher;

const paths = workspace.paths;

pub const Options = struct {
    case_sensitive: bool = false,
    regex: bool = false,
    show_hidden: bool = false,
    max_results: u32 = 2000,
    max_file_size: u64 = 2 * 1024 * 1024,
};

/// One line with a match. `text` is a piece of the line around it, at most
/// snippet_max bytes; `match_start`/`match_len` are inside `text`.
pub const Hit = extern struct {
    path: [*:0]const u8,
    /// 1-based, like editors show.
    line: u32,
    /// Byte offset of the match in the whole line.
    column: u32,
    text: [*]const u8,
    text_len: u32,
    match_start: u32,
    match_len: u32,
};

pub const Callbacks = extern struct {
    context: ?*anyopaque = null,
    /// A batch of hits; valid only during the call.
    on_hits: ?*const fn (context: ?*anyopaque, hits: [*]const Hit, count: usize) callconv(.c) void = null,
    /// The search ended on its own: `truncated` when it hit max_results.
    /// Not called after cancel.
    on_done: ?*const fn (context: ?*anyopaque, truncated: bool, files: u32) callconv(.c) void = null,
};

pub const snippet_max = 240;
const batch_size = 64;
const sniff_size = 8 * 1024;

pub const Search = struct {
    gpa: std.mem.Allocator,
    root: []u8,
    matcher: Matcher,
    options: Options,
    callbacks: Callbacks,
    cancelled: std.atomic.Value(bool) = .init(false),
    thread: std.Thread = undefined,
    // Owned by the thread while it runs.
    batch: std.ArrayList(Hit) = .empty,
    batch_arena: std.heap.ArenaAllocator,
    results: u32 = 0,
    files: u32 = 0,
    buffer: std.ArrayList(u8) = .empty,

    /// Starts searching `query` under `root` (inside an authorized
    /// directory). An invalid regex fails here, before any thread.
    pub fn start(gpa: std.mem.Allocator, registry: *workspace.Registry, root: []const u8, query: []const u8, options: Options, callbacks: Callbacks) !*Search {
        var buf: paths.Buffer = undefined;
        const real = try registry.resolve(root, &buf);
        if (!paths.isDirectory(real)) return error.NotDirectory;
        var matcher = try Matcher.init(gpa, query, options.case_sensitive, options.regex);
        errdefer matcher.deinit();
        const self = try gpa.create(Search);
        errdefer gpa.destroy(self);
        self.* = .{
            .gpa = gpa,
            .root = try gpa.dupe(u8, real),
            .matcher = matcher,
            .options = options,
            .callbacks = callbacks,
            .batch_arena = .init(gpa),
        };
        errdefer gpa.free(self.root);
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }

    /// Stops the search (if still running) and frees it. No callback runs
    /// after this returns.
    pub fn cancel(self: *Search) void {
        self.cancelled.store(true, .release);
        self.thread.join();
        self.matcher.deinit();
        self.batch.deinit(self.gpa);
        self.batch_arena.deinit();
        self.buffer.deinit(self.gpa);
        self.gpa.free(self.root);
        self.gpa.destroy(self);
    }

    fn run(self: *Search) void {
        var walker = Walker.init(self.gpa, self.root, .{ .show_hidden = self.options.show_hidden, .cancel = &self.cancelled }) catch return;
        defer walker.deinit();
        const finished = walker.walk("", self, visit) catch false;
        if (self.cancelled.load(.acquire)) return;
        self.flush();
        const truncated = !finished and self.results >= self.options.max_results;
        if (self.callbacks.on_done) |done| done(self.callbacks.context, truncated, self.files);
    }

    fn visit(context: *anyopaque, rel: []const u8, size: u64) bool {
        const self: *Search = @ptrCast(@alignCast(context));
        if (self.cancelled.load(.acquire)) return false;
        if (size == 0 or size > self.options.max_file_size) return true;
        self.searchFile(rel) catch {};
        return self.results < self.options.max_results and !self.cancelled.load(.acquire);
    }

    fn searchFile(self: *Search, rel: []const u8) !void {
        const bytes = try self.read(rel) orelse return;
        self.files += 1;
        if (std.mem.indexOfScalar(u8, bytes[0..@min(bytes.len, sniff_size)], 0) != null) return;
        var line_no: u32 = 1;
        var line_start: usize = 0;
        var counted_to: usize = 0;
        var from: usize = 0;
        while (from < bytes.len) {
            const found = self.matcher.find(bytes, from) orelse break;
            // Count lines up to the match.
            line_no += @intCast(std.mem.count(u8, bytes[counted_to..found.start], "\n"));
            counted_to = found.start;
            line_start = if (std.mem.lastIndexOfScalar(u8, bytes[0..found.start], '\n')) |nl| nl + 1 else 0;
            const line_end = std.mem.indexOfScalarPos(u8, bytes, found.start, '\n') orelse bytes.len;
            try self.add(rel, bytes[line_start..line_end], line_no, found.start - line_start, @min(found.end, line_end) - found.start);
            if (self.results >= self.options.max_results) return;
            // One hit per line: go on from the next line.
            from = line_end + 1;
        }
    }

    /// The file's bytes in a buffer reused across files.
    fn read(self: *Search, rel: []const u8) !?[]const u8 {
        var path_buf: paths.Buffer = undefined;
        const path = try fs.join(&path_buf, self.root, rel);
        const file = fs.File.openRead(path, .{ .follow = false }) catch return null;
        defer file.close();
        self.buffer.clearRetainingCapacity();
        try fs.appendUpTo(self.gpa, file, &self.buffer, self.options.max_file_size);
        if (self.buffer.items.len > self.options.max_file_size) return null;
        return self.buffer.items;
    }

    fn add(self: *Search, rel: []const u8, line: []const u8, line_no: u32, column: usize, len: usize) !void {
        const a = self.batch_arena.allocator();
        const cut = snippet(line, column, len);
        const text = try a.dupe(u8, line[cut.start..cut.end]);
        try self.batch.append(self.gpa, .{
            .path = (try a.dupeZ(u8, rel)).ptr,
            .line = line_no,
            .column = @intCast(column),
            .text = text.ptr,
            .text_len = @intCast(text.len),
            .match_start = @intCast(column - cut.start),
            .match_len = @intCast(@min(len, cut.end - column)),
        });
        self.results += 1;
        if (self.batch.items.len >= batch_size) self.flush();
    }

    fn flush(self: *Search) void {
        if (self.batch.items.len == 0) return;
        if (!self.cancelled.load(.acquire)) {
            if (self.callbacks.on_hits) |on_hits| on_hits(self.callbacks.context, self.batch.items.ptr, self.batch.items.len);
        }
        self.batch.clearRetainingCapacity();
        _ = self.batch_arena.reset(.retain_capacity);
    }
};

/// The part of a long line shown around the match, cut on UTF-8 boundaries
/// and without the indentation.
pub fn snippet(line: []const u8, column: usize, len: usize) struct { start: usize, end: usize } {
    var start: usize = 0;
    while (start < column and (line[start] == ' ' or line[start] == '\t')) start += 1;
    if (column - start > snippet_max / 3) start = column - snippet_max / 3;
    while (start > 0 and start < line.len and line[start] & 0xC0 == 0x80) start -= 1;
    var end = @min(line.len, start + snippet_max);
    if (end < column + len) end = @min(line.len, column + len);
    while (end < line.len and line[end] & 0xC0 == 0x80) end += 1;
    return .{ .start = start, .end = end };
}

test {
    _ = @import("content_test.zig");
    _ = @import("content_match.zig");
}
