//! One folder's contents for the tree, read only when the folder is opened
//! (docs/spec/explorer.md): folders first, then files, in natural order.

const std = @import("std");
const c = std.c;
const workspace = @import("../workspace/workspace.zig");
const errors = @import("errors.zig");
const natural = @import("natural.zig");

const paths = workspace.paths;
pub const Error = errors.Error;

extern "c" fn dirfd(dir: *c.DIR) c.fd_t;

pub const Kind = enum(u8) { file = 0, directory = 1, symlink = 2, other = 3 };

pub const Entry = struct {
    name: []const u8,
    kind: Kind,
    /// Bytes, for files; 0 otherwise.
    size: u64,
    /// A symbolic link whose target is a folder: listed with the folders.
    link_to_directory: bool = false,

    fn sortsAsDirectory(self: Entry) bool {
        return self.kind == .directory or self.link_to_directory;
    }
};

/// Owns the names; free with deinit.
pub const Listing = struct {
    arena: std.heap.ArenaAllocator,
    entries: []Entry,

    pub fn deinit(self: *Listing) void {
        self.arena.deinit();
    }
};

/// Lists the folder at `path`, which must resolve inside an authorized
/// directory. `.`, `..` and `.git` are left out (`.git` never shows).
pub fn list(gpa: std.mem.Allocator, registry: *workspace.Registry, path: []const u8) Error!Listing {
    var real_buf: paths.Buffer = undefined;
    const real = try registry.resolve(path, &real_buf);
    var z_buf: paths.Buffer = undefined;
    const z = try paths.terminate(real, &z_buf);
    const dir = c.opendir(z.ptr) orelse return errors.fromErrno();
    defer _ = c.closedir(dir);
    const fd = dirfd(dir);

    var arena: std.heap.ArenaAllocator = .init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    var entries: std.ArrayList(Entry) = .empty;
    while (c.readdir(dir)) |ent| {
        const name = ent.name[0..ent.namlen];
        if (skipped(name)) continue;
        // Gone between readdir and stat: skip it, the watcher reports it.
        const entry = describe(fd, name) orelse continue;
        try entries.append(a, .{
            .name = try a.dupe(u8, name),
            .kind = entry.kind,
            .size = entry.size,
            .link_to_directory = entry.link_to_directory,
        });
    }
    std.mem.sort(Entry, entries.items, {}, treeOrder);
    return .{ .arena = arena, .entries = entries.items };
}

fn skipped(name: []const u8) bool {
    return std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..") or std.mem.eql(u8, name, ".git");
}

fn describe(dir_fd: c.fd_t, name: []const u8) ?Entry {
    var z_buf: paths.Buffer = undefined;
    const z = paths.terminate(name, &z_buf) catch return null;
    var st: c.Stat = undefined;
    if (c.fstatat(dir_fd, z.ptr, &st, c.AT.SYMLINK_NOFOLLOW) != 0) return null;
    const kind = kindOf(st.mode);
    var entry: Entry = .{ .name = name, .kind = kind, .size = if (kind == .file) @intCast(st.size) else 0 };
    if (kind == .symlink) {
        var target: c.Stat = undefined;
        entry.link_to_directory = c.fstatat(dir_fd, z.ptr, &target, 0) == 0 and kindOf(target.mode) == .directory;
    }
    return entry;
}

fn kindOf(mode: c.mode_t) Kind {
    return switch (mode & c.S.IFMT) {
        c.S.IFREG => .file,
        c.S.IFDIR => .directory,
        c.S.IFLNK => .symlink,
        else => .other,
    };
}

fn treeOrder(_: void, a: Entry, b: Entry) bool {
    if (a.sortsAsDirectory() != b.sortsAsDirectory()) return a.sortsAsDirectory();
    return natural.lessThan(a.name, b.name);
}

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

test "lists folders first in natural order, with kinds and sizes" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("src");
    try dir.makeDir("Docs");
    try dir.makeDir(".git/objects");
    try dir.writeFile("file10.txt", "0123456789");
    try dir.writeFile("file2.txt", "ab");
    try dir.writeFile(".env", "");
    try testing.expectEqual(@as(c_int, 0), c.symlink("src", (try dir.join("link-to-src")).ptr));
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());

    var listing = try list(testing.allocator, &registry, dir.path());
    defer listing.deinit();
    const want = [_][]const u8{ "Docs", "link-to-src", "src", ".env", "file2.txt", "file10.txt" };
    try testing.expectEqual(want.len, listing.entries.len);
    for (want, listing.entries) |name, entry| try testing.expectEqualStrings(name, entry.name);
    try testing.expectEqual(Kind.directory, listing.entries[0].kind);
    try testing.expectEqual(Kind.symlink, listing.entries[1].kind);
    try testing.expect(listing.entries[1].link_to_directory);
    try testing.expectEqual(@as(u64, 10), listing.entries[5].size);
}

test "listing outside the workspace is refused" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("inside");
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(try dir.join("inside"));
    try testing.expectError(error.Outside, list(testing.allocator, &registry, dir.path()));
    try testing.expectError(error.Outside, list(testing.allocator, &registry, try dir.join("inside/..")));
}
