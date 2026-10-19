//! What is under the pointer for ⌘+hover and ⌘+click: an OSC 8 hyperlink a
//! program printed, or a URL or path found in the text (link_detect.zig).
//! Reads libghostty-vt's render state, so it is one of the files allowed to
//! import it (ADR 0003).

const std = @import("std");
const builtin = @import("builtin");
const fs = @import("../../shared/fs.zig");
const vt = @import("ghostty-vt");
const render = @import("render.zig");
const detect = @import("link_detect.zig");

pub const Kind = detect.Kind;

/// A viewport cell. Mirrors the fields of cadex_terminal_link.
pub const Point = struct { col: u16, row: u16 };

pub const Link = struct {
    kind: Kind,
    /// What to open: the URL, or the absolute path of a file that exists.
    target: []u8,
    /// First and last cell of the link on screen, to underline it.
    start: Point,
    end: Point,

    pub fn deinit(self: Link, gpa: std.mem.Allocator) void {
        gpa.free(self.target);
    }
};

/// The OSC 8 hyperlink at a cell. Hold the session lock and call right
/// after Renderer.capture: it reads the pages the render state points to.
pub fn hyperlinkAt(gpa: std.mem.Allocator, state: *vt.RenderState, at: Point) !?Link {
    if (at.col >= state.cols or at.row >= state.rows) return null;
    const pin = state.row_data.items(.pin)[at.row];
    const page = pin.node.page();
    const rac = page.getRowAndCell(at.col, pin.y);
    if (!rac.cell.hyperlink) return null;
    const id = page.lookupHyperlink(rac.cell) orelse return null;
    const uri = page.hyperlink_set.get(page.memory, id).uri.slice(page.memory);

    var cells = try state.linkCells(gpa, .{ .x = at.col, .y = at.row });
    defer cells.deinit(gpa);
    const keys = cells.keys();
    if (keys.len == 0) return null;
    return .{
        .kind = .url,
        .target = try gpa.dupe(u8, uri),
        .start = .{ .col = keys[0].x, .row = @intCast(keys[0].y) },
        .end = .{ .col = keys[keys.len - 1].x, .row = @intCast(keys[keys.len - 1].y) },
    };
}

/// Where relative paths and ~ resolve.
pub const Places = struct { cwd: ?[]const u8, home: ?[]const u8 };

/// A URL or existing path in the text around a cell, from the frame the
/// renderer just built. Lines wrapped by width are joined, so a long URL
/// split over two rows is one link.
pub fn detectAt(gpa: std.mem.Allocator, renderer: *const render.Renderer, at: Point, places: Places) !?Link {
    const frame = &renderer.frame;
    if (at.col >= frame.cols or at.row >= frame.rows) return null;
    const wraps = renderer.state.row_data.items(.raw);

    var first = at.row;
    while (first > 0 and wraps[first - 1].wrap) first -= 1;
    var last = at.row;
    while (last + 1 < frame.rows and wraps[last].wrap) last += 1;

    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    var cells: std.ArrayList(Point) = .empty;
    defer cells.deinit(gpa);
    var clicked: ?usize = null;
    for (first..last + 1) |row| {
        for (0..frame.cols) |col| {
            const cell = frame.cells[row * frame.cols + col];
            if (cell.flags & render.CellFlags.spacer != 0) continue;
            const here: Point = .{ .col = @intCast(col), .row = @intCast(row) };
            // A wide character's second half points at its first half.
            const covers_click = row == at.row and (col == at.col or
                (col + 1 == at.col and cell.flags & render.CellFlags.wide != 0));
            if (covers_click) clicked = text.items.len;
            const bytes = if (cell.text_len == 0) " " else frame.text[cell.text_offset..][0..cell.text_len];
            try text.appendSlice(gpa, bytes);
            for (bytes) |_| try cells.append(gpa, here);
        }
    }

    const span = detect.findAt(text.items, clicked orelse return null) orelse return null;
    const found = text.items[span.start..span.end];
    const target = switch (span.kind) {
        .url => if (std.ascii.startsWithIgnoreCase(found, "www."))
            try std.mem.concat(gpa, u8, &.{ "https://", found })
        else
            try gpa.dupe(u8, found),
        .path => try resolvePath(gpa, found, places) orelse return null,
        .none => return null,
    };
    return .{ .kind = span.kind, .target = target, .start = cells.items[span.start], .end = cells.items[span.end - 1] };
}

/// The absolute path of `raw` if that file exists, trying it as printed
/// and without a ":line:col" suffix. Caller frees.
fn resolvePath(gpa: std.mem.Allocator, raw: []const u8, places: Places) !?[]u8 {
    const candidates = [_][]const u8{ raw, detect.withoutLineSuffix(raw) };
    for (candidates) |candidate| {
        const absolute = try absolutePath(gpa, candidate, places) orelse continue;
        if (exists(absolute)) return absolute;
        gpa.free(absolute);
    }
    return null;
}

fn absolutePath(gpa: std.mem.Allocator, path: []const u8, places: Places) !?[]u8 {
    if (path.len == 0) return null;
    if (path[0] == '/') return try gpa.dupe(u8, path);
    if (std.mem.startsWith(u8, path, "~/")) {
        const home = places.home orelse return null;
        return try std.mem.concat(gpa, u8, &.{ home, path[1..] });
    }
    const cwd = places.cwd orelse return null;
    return try std.mem.concat(gpa, u8, &.{ cwd, "/", path });
}

/// Follows a last link, like access(2): a broken link is no file.
fn exists(path: []const u8) bool {
    return fs.info(path, true) != null;
}

/// Decodes the directory of an OSC 7 report ("file://host/Users/x%20y")
/// into `buf`. Null when it is not a file URL.
pub fn directoryFromOsc7(report: []const u8, buf: []u8) ?[]const u8 {
    const prefix = "file://";
    if (!std.mem.startsWith(u8, report, prefix)) return null;
    const rest = report[prefix.len..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
    const encoded = rest[slash..];
    if (encoded.len > buf.len) return null;
    @memcpy(buf[0..encoded.len], encoded);
    const decoded = std.Uri.percentDecodeInPlace(buf[0..encoded.len]);
    return if (builtin.os.tag == .windows) windowsDirectory(decoded) else decoded;
}

/// A reported Windows folder ("/C:/Users/x", or "///server/share" for a
/// network one) as Windows writes it: "C:\Users\x", "\\server\share". Any
/// other path (a Linux one from a WSL shell) stays as it came.
pub fn windowsDirectory(decoded: []u8) []u8 {
    const p = if (decoded.len > 0 and decoded[0] == '/') decoded[1..] else decoded;
    const drive = p.len >= 2 and std.ascii.isAlphabetic(p[0]) and p[1] == ':';
    const network = std.mem.startsWith(u8, p, "//");
    if (!drive and !network) return decoded;
    std.mem.replaceScalar(u8, p, '/', '\\');
    return p;
}

const testing = std.testing;

test "Windows folders reported by PowerShell keep the drive and the backslashes" {
    var buf: [64]u8 = undefined;
    const drive = "/C:/Users/Ana Lu";
    @memcpy(buf[0..drive.len], drive);
    try testing.expectEqualStrings("C:\\Users\\Ana Lu", windowsDirectory(buf[0..drive.len]));
    const share = "///server/share/x";
    @memcpy(buf[0..share.len], share);
    try testing.expectEqualStrings("\\\\server\\share\\x", windowsDirectory(buf[0..share.len]));
    const wsl = "/home/ana";
    @memcpy(buf[0..wsl.len], wsl);
    try testing.expectEqualStrings("/home/ana", windowsDirectory(buf[0..wsl.len]));
}

test "OSC 7 reports decode to a directory" {
    var buf: [256]u8 = undefined;
    try testing.expectEqualStrings("/Users/cadu/Meus Projetos", directoryFromOsc7("file://mac.local/Users/cadu/Meus%20Projetos", &buf).?);
    try testing.expectEqualStrings("/Users/x", directoryFromOsc7("file://localhost/Users/x", &buf).?);
    try testing.expect(directoryFromOsc7("http://x/y", &buf) == null);
}

test "paths resolve against the shell's directory and home" {
    const gpa = testing.allocator;
    const places: Places = .{ .cwd = "/usr", .home = "/var" };
    const bin = (try resolvePath(gpa, "bin", places)).?;
    defer gpa.free(bin);
    try testing.expectEqualStrings("/usr/bin", bin);
    const at_line = (try resolvePath(gpa, "/usr/bin:12:3", places)).?;
    defer gpa.free(at_line);
    try testing.expectEqualStrings("/usr/bin", at_line);
    try testing.expect(try resolvePath(gpa, "nao/existe", places) == null);
    try testing.expect(try resolvePath(gpa, "bin", .{ .cwd = null, .home = null }) == null);
}
