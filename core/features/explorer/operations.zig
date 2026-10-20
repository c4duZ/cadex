//! Changes to files and folders: create, rename, move, copy. Deleting goes
//! to the system Trash, which the app does (docs/spec/explorer.md). Every
//! path passes the workspace check, and the result is a canonical path.

const std = @import("std");
const fs = @import("../../shared/fs.zig");
const language = @import("../../shared/language.zig");
const workspace = @import("../workspace/workspace.zig");
const errors = @import("errors.zig");

const paths = workspace.paths;
const Registry = workspace.Registry;
pub const Error = errors.Error;

/// Creates an empty file; fails if the name is taken.
pub fn createFile(registry: *Registry, path: []const u8) Error!void {
    var buf: paths.Buffer = undefined;
    try fs.createNew(try registry.resolveEntry(path, &buf));
}

/// Creates an empty folder; fails if the name is taken.
pub fn createDirectory(registry: *Registry, path: []const u8) Error!void {
    var buf: paths.Buffer = undefined;
    try fs.makeDirectory(try registry.resolveEntry(path, &buf));
}

/// Gives `path` a new name in the same folder. Taken names are refused;
/// changing only the case (readme -> README) is allowed. Returns the new
/// path, in `out`.
pub fn rename(registry: *Registry, path: []const u8, new_name: []const u8, out: *paths.Buffer) Error![]const u8 {
    if (!paths.isPlainName(new_name)) return error.NameInvalid;
    var from_buf: paths.Buffer = undefined;
    const from = try registry.resolveEntry(path, &from_buf);
    const parent = std.fs.path.dirname(from) orelse return error.NameInvalid;
    const to = try join(out, parent, new_name);
    if (std.mem.eql(u8, from, to)) return to;
    const case_only = std.ascii.eqlIgnoreCase(std.fs.path.basename(from), new_name);
    try fs.rename(from, to, !case_only);
    return to;
}

/// Moves `path` into the folder `destination`, keeping its name. Returns
/// the new path, in `out`.
pub fn move(registry: *Registry, path: []const u8, destination: []const u8, out: *paths.Buffer) Error![]const u8 {
    var from_buf: paths.Buffer = undefined;
    const from = try registry.resolveEntry(path, &from_buf);
    var dir_buf: paths.Buffer = undefined;
    const dir = try targetFolder(registry, from, destination, &dir_buf);
    const to = try join(out, dir, std.fs.path.basename(from));
    if (std.mem.eql(u8, from, to)) return to;
    try fs.rename(from, to, true);
    return to;
}

/// Copies `path` (a folder with everything in it) into `destination`.
/// Next to a namesake, the copy is named "name copy.ext", then
/// "name copy 2.ext" ("cópia" in Portuguese, as the app's language). Returns the new path, in `out`.
pub fn copy(registry: *Registry, path: []const u8, destination: []const u8, out: *paths.Buffer) Error![]const u8 {
    var from_buf: paths.Buffer = undefined;
    const from = try registry.resolveEntry(path, &from_buf);
    var dir_buf: paths.Buffer = undefined;
    const dir = try targetFolder(registry, from, destination, &dir_buf);
    const to = try freeName(out, dir, std.fs.path.basename(from));
    try fs.copyTree(from, to);
    return to;
}

/// The canonical destination folder, refusing a folder inside `from`.
fn targetFolder(registry: *Registry, from: []const u8, destination: []const u8, out: *paths.Buffer) Error![]const u8 {
    const dir = try registry.resolve(destination, out);
    if (!paths.isDirectory(dir)) return error.NotDirectory;
    if (paths.isWithin(from, dir)) return error.IntoItself;
    return dir;
}

fn join(out: *paths.Buffer, dir: []const u8, name: []const u8) Error![]const u8 {
    return fs.join(out, dir, name);
}

/// `name` in `dir` if free, else "stem copy.ext", "stem copy 2.ext", ...
fn freeName(out: *paths.Buffer, dir: []const u8, name: []const u8) Error![]const u8 {
    const candidate = try join(out, dir, name);
    if (!exists(candidate)) return candidate;
    const dot = std.mem.lastIndexOfScalar(u8, name, '.');
    const split = if (dot) |d| (if (d == 0) name.len else d) else name.len;
    const stem = name[0..split];
    const ext = name[split..];
    var n: usize = 1;
    while (n < 1000) : (n += 1) {
        var name_buf: paths.Buffer = undefined;
        const word = language.t("copy", "cópia");
        const numbered = if (n == 1)
            std.fmt.bufPrint(&name_buf, "{s} {s}{s}", .{ stem, word, ext })
        else
            std.fmt.bufPrint(&name_buf, "{s} {s} {d}{s}", .{ stem, word, n, ext });
        const next = try join(out, dir, numbered catch return error.NameTooLong);
        if (!exists(next)) return next;
    }
    return error.AlreadyExists;
}

const exists = fs.exists;

const testing = std.testing;
const sep: []const u8 = &.{fs.sep};
const TestDir = @import("../../shared/test_dir.zig").TestDir;

fn authorized(dir: *TestDir) !Registry {
    var registry = Registry.init(testing.allocator);
    errdefer registry.deinit();
    _ = try registry.authorize(dir.path());
    return registry;
}

test "creates files and folders, refusing taken names" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = try authorized(&dir);
    defer registry.deinit();

    try createFile(&registry, try dir.join("new.txt"));
    try createDirectory(&registry, try dir.join("folder"));
    try testing.expect(dir.exists("new.txt") and dir.exists("folder"));
    try testing.expectError(error.AlreadyExists, createFile(&registry, try dir.join("new.txt")));
    try testing.expectError(error.AlreadyExists, createDirectory(&registry, try dir.join("folder")));
    try testing.expectError(error.Outside, createFile(&registry, try dir.join("../escape.txt")));
}

test "renames in place; a taken name is refused, a case change is not" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.writeFile("a.txt", "a");
    try dir.writeFile("b.txt", "b");
    var registry = try authorized(&dir);
    defer registry.deinit();

    var out: paths.Buffer = undefined;
    try testing.expectError(error.AlreadyExists, rename(&registry, try dir.join("a.txt"), "b.txt", &out));
    try testing.expect(dir.exists("a.txt"));
    try testing.expectError(error.NameInvalid, rename(&registry, try dir.join("a.txt"), "../x", &out));
    const renamed = try rename(&registry, try dir.join("a.txt"), "c.txt", &out);
    try testing.expect(std.mem.endsWith(u8, renamed, sep ++ "c.txt"));
    _ = try rename(&registry, try dir.join("c.txt"), "C.txt", &out);
    try testing.expect(dir.exists("C.txt"));
}

test "moves into another folder, never into itself" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("src/inner");
    try dir.makeDir("dest");
    try dir.writeFile("src/file.txt", "x");
    var registry = try authorized(&dir);
    defer registry.deinit();

    var a: [1024]u8 = undefined;
    var b: [1024]u8 = undefined;
    var out: paths.Buffer = undefined;
    _ = try move(&registry, try dir.joinInto(&a, "src/file.txt"), try dir.joinInto(&b, "dest"), &out);
    try testing.expect(dir.exists("dest/file.txt") and !dir.exists("src/file.txt"));
    try testing.expectError(error.IntoItself, move(&registry, try dir.joinInto(&a, "src"), try dir.joinInto(&b, "src/inner"), &out));
    try testing.expectError(error.IntoItself, move(&registry, try dir.joinInto(&a, "src"), try dir.joinInto(&b, "src"), &out));
    try testing.expectError(error.Outside, move(&registry, try dir.joinInto(&a, "dest/file.txt"), try dir.joinInto(&b, ".."), &out));
}

test "copies files and folders, naming the copy next to a namesake" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("folder/sub");
    try dir.writeFile("folder/sub/deep.txt", "deep");
    try dir.writeFile("notes.md", "hi");
    var registry = try authorized(&dir);
    defer registry.deinit();

    var a: [1024]u8 = undefined;
    var out: paths.Buffer = undefined;
    const first = try copy(&registry, try dir.joinInto(&a, "notes.md"), dir.path(), &out);
    try testing.expect(std.mem.endsWith(u8, first, sep ++ "notes copy.md"));
    const second = try copy(&registry, try dir.joinInto(&a, "notes.md"), dir.path(), &out);
    try testing.expect(std.mem.endsWith(u8, second, sep ++ "notes copy 2.md"));
    _ = try copy(&registry, try dir.joinInto(&a, "folder"), dir.path(), &out);
    try testing.expect(dir.exists("folder copy/sub/deep.txt"));
    try testing.expectError(error.IntoItself, copy(&registry, try dir.joinInto(&a, "folder"), try dir.join("folder/sub"), &out));
}
