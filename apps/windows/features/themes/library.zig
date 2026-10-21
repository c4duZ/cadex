//! Every theme the user can pick, as the Mac's ThemeLibrary.swift: theirs,
//! from the themes folder (%APPDATA%\Cadex\themes, beside settings.json; one
//! Cadex theme file each), then the built-in catalog. Read when asked and
//! freed by the one who asked (the themes page, ⌘K's list), like the
//! catalog (docs/spec/themes.md).

const std = @import("std");
const w = @import("win32");
const t = @import("strings").t;
const strings = @import("strings");
const theme = @import("theme.zig");
const catalog = @import("catalog.zig");
const file = @import("file.zig");

const Family = theme.Family;
const c = w.c;

/// Ids of the user's themes start with this, so they never take a
/// built-in one's place.
pub const user_prefix = "user:";

/// %APPDATA%\Cadex\themes; owned by the caller.
pub fn folder(gpa: std.mem.Allocator) ![]u8 {
    return w.files.appData(gpa, "themes");
}

/// The user's themes then the built-in ones, and the files of the folder
/// that could not be read ("file.json: field: why"). deinit frees it all.
pub const List = struct {
    arena: std.heap.ArenaAllocator,
    families: []const Family = &.{},
    problems: []const []const u8 = &.{},

    pub fn deinit(self: *List) void {
        self.arena.deinit();
    }
};

pub fn all(gpa: std.mem.Allocator, dir: []const u8) List {
    var list: List = .{ .arena = .init(gpa) };
    const a = list.arena.allocator();
    var families: std.ArrayList(Family) = .empty;
    var problems: std.ArrayList([]const u8) = .empty;
    userThemes(gpa, a, dir, &families, &problems);
    catalog.appendAll(gpa, a, &families) catch |err| std.log.warn("catalog.json: {s}", .{@errorName(err)});
    list.families = families.items;
    list.problems = problems.items;
    return list;
}

/// One family by id, its strings in `arena`: a user's theme reads only its
/// own file.
pub fn family(gpa: std.mem.Allocator, arena: std.mem.Allocator, dir: []const u8, id: []const u8) ?Family {
    if (!std.mem.startsWith(u8, id, user_prefix)) return catalog.find(gpa, arena, id);
    const stem = id[user_prefix.len..];
    const name = std.fmt.allocPrint(arena, "{s}.json", .{stem}) catch return null;
    var problem: theme.Problem = .{};
    return userFamily(gpa, arena, dir, name, &problem) catch null;
}

/// The folder's .json files, sorted by name as the Mac lists them.
fn userThemes(gpa: std.mem.Allocator, arena: std.mem.Allocator, dir: []const u8, families: *std.ArrayList(Family), problems: *std.ArrayList([]const u8)) void {
    const names = jsonFiles(arena, dir) catch return;
    std.mem.sort([]const u8, names, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    for (names) |name| {
        var problem: theme.Problem = .{};
        const f = userFamily(gpa, arena, dir, name, &problem) catch {
            const line = std.fmt.allocPrint(arena, "{s}: {s}: {s}", .{ name, problem.field, problem.message }) catch continue;
            problems.append(arena, line) catch {};
            continue;
        };
        families.append(arena, f) catch {};
    }
}

fn userFamily(gpa: std.mem.Allocator, arena: std.mem.Allocator, dir: []const u8, name: []const u8, problem: *theme.Problem) !Family {
    const path = try std.fmt.allocPrint(gpa, "{s}\\{s}", .{ dir, name });
    defer gpa.free(path);
    const data = w.files.read(gpa, path, 1024 * 1024) orelse {
        problem.* = .{ .field = "(file)", .message = t("could not be read", "não deu para ler") };
        return error.InvalidTheme;
    };
    defer gpa.free(data);
    const th = try file.read(arena, gpa, data, problem);
    const stem = name[0 .. name.len - ".json".len];
    return .{
        .id = try std.fmt.allocPrint(arena, user_prefix ++ "{s}", .{stem}),
        .name = th.name,
        .description = try userDescription(arena, name),
        .source = "user",
        .dark = if (th.dark) th else null,
        .light = if (th.dark) null else th,
    };
}

/// Not through strings.t: the text is made per file, not a fixed one.
fn userDescription(arena: std.mem.Allocator, name: []const u8) ![]u8 {
    if (strings.language == .pt) return std.fmt.allocPrint(arena, "Seu tema: {s}", .{name});
    return std.fmt.allocPrint(arena, "Your theme: {s}", .{name});
}

fn jsonFiles(arena: std.mem.Allocator, dir: []const u8) ![][]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    const pattern = try std.fmt.allocPrint(arena, "{s}\\*.json", .{dir});
    const wide = try std.unicode.wtf8ToWtf16LeAllocZ(arena, pattern);
    var data: c.WIN32_FIND_DATAW = undefined;
    const find = c.FindFirstFileW(wide.ptr, &data);
    if (find == c.INVALID_HANDLE_VALUE) return names.items;
    defer _ = c.FindClose(find);
    while (true) {
        const name = try std.unicode.wtf16LeToWtf8Alloc(arena, std.mem.sliceTo(&data.cFileName, 0));
        // "*.json" also matches "x.json5" by its short name: keep exact ones.
        const is_file = data.dwFileAttributes & c.FILE_ATTRIBUTE_DIRECTORY == 0;
        if (is_file and std.ascii.endsWithIgnoreCase(name, ".json")) try names.append(arena, name);
        if (c.FindNextFileW(find, &data) == 0) break;
    }
    return names.items;
}

/// Saves `th` in the folder under a file name from its name, and returns
/// its id (owned by the caller). A theme of the same name is replaced.
pub fn save(gpa: std.mem.Allocator, dir: []const u8, th: theme.Theme) ![]u8 {
    const stem = try slug(gpa, th.name);
    defer gpa.free(stem);
    const text = try file.write(gpa, th);
    defer gpa.free(text);
    const path = try std.fmt.allocPrint(gpa, "{s}\\{s}.json", .{ dir, stem });
    defer gpa.free(path);
    try w.files.writeAtomic(gpa, path, text);
    return std.fmt.allocPrint(gpa, user_prefix ++ "{s}", .{stem});
}

/// "Tokyo Night (Storm)" → "tokyo-night-storm"; "theme" when nothing is left.
/// Bytes past ASCII stay (letters of other alphabets, as the Mac keeps them).
pub fn slug(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (name) |ch| {
        const keep = std.ascii.isAlphanumeric(ch) or ch >= 0x80;
        if (keep) {
            try out.append(gpa, std.ascii.toLower(ch));
        } else if (out.items.len > 0 and out.items[out.items.len - 1] != '-') {
            try out.append(gpa, '-');
        }
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == '-') _ = out.pop();
    if (out.items.len == 0) try out.appendSlice(gpa, "theme");
    return out.toOwnedSlice(gpa);
}

const testing = std.testing;

test "a slug from a theme's name" {
    const cases = [_][2][]const u8{ .{ "Tokyo Night (Storm)", "tokyo-night-storm" }, .{ "  --  ", "theme" }, .{ "Café", "café" } };
    for (cases) |case| {
        const got = try slug(testing.allocator, case[0]);
        defer testing.allocator.free(got);
        try testing.expectEqualStrings(case[1], got);
    }
}

test "a saved theme is found by its id, listed first, and a broken file is named" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(dir);
    const id = try save(testing.allocator, dir, file.sample);
    defer testing.allocator.free(id);
    try testing.expectEqualStrings("user:meu-tema", id);
    const broken = try std.fmt.allocPrint(testing.allocator, "{s}\\broken.json", .{dir});
    defer testing.allocator.free(broken);
    try w.files.writeAtomic(testing.allocator, broken, "{\"name\": \"x\"}");

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const found = family(testing.allocator, arena.allocator(), dir, id).?;
    try testing.expectEqualStrings(file.sample.name, found.name);
    try testing.expect(found.light != null and found.dark == null);

    var list = all(testing.allocator, dir);
    defer list.deinit();
    try testing.expectEqualStrings(id, list.families[0].id);
    try testing.expectEqualStrings(catalog.default_id, list.families[1].id);
    try testing.expectEqual(@as(usize, 1), list.problems.len);
    try testing.expect(std.mem.startsWith(u8, list.problems[0], "broken.json: "));
}
