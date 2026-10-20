//! Addresses of local files in the app's own pages: a Windows path as the
//! path of an https:// address on a host of ours, and back. Pure, so the
//! rules are tested here.

const std = @import("std");

/// "C:\notes\a b.md" under "https://note.cadex.example/" →
/// "https://note.cadex.example/C:/notes/a%20b.md". Backslashes become
/// slashes; anything but letters, digits, "-._~/:" is percent-encoded
/// (spaces, "#", "?", "%", non-ASCII as UTF-8 bytes).
pub fn fileUrl(gpa: std.mem.Allocator, prefix: []const u8, path: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, prefix);
    var rest = path;
    // \\?\C:\... (a long path) and a leading slash are not part of the address.
    if (std.mem.startsWith(u8, rest, "\\\\?\\")) rest = rest[4..];
    while (rest.len > 0 and (rest[0] == '\\' or rest[0] == '/')) rest = rest[1..];
    for (rest) |b| {
        if (b == '\\') {
            try out.append(gpa, '/');
        } else if (std.ascii.isAlphanumeric(b) or std.mem.indexOfScalar(u8, "-._~/:", b) != null) {
            try out.append(gpa, b);
        } else {
            try out.print(gpa, "%{X:0>2}", .{b});
        }
    }
    return out.toOwnedSlice(gpa);
}

pub const Local = struct {
    /// Owned Windows path ("C:\notes\b.md").
    path: []u8,
    /// After "#", without it (not owned: a slice of the url).
    fragment: ?[]const u8,
};

/// The file behind an address of ours, or null for another address.
pub fn localPath(gpa: std.mem.Allocator, prefix: []const u8, url: []const u8) !?Local {
    if (url.len < prefix.len or !std.ascii.eqlIgnoreCase(url[0..prefix.len], prefix)) return null;
    var rest = url[prefix.len..];
    var fragment: ?[]const u8 = null;
    if (std.mem.indexOfScalar(u8, rest, '#')) |h| {
        fragment = rest[h + 1 ..];
        rest = rest[0..h];
    }
    if (std.mem.indexOfScalar(u8, rest, '?')) |q| rest = rest[0..q];
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < rest.len) : (i += 1) {
        const b = rest[i];
        if (b == '%' and i + 2 < rest.len) {
            if (std.fmt.parseInt(u8, rest[i + 1 .. i + 3], 16)) |byte| {
                try out.append(gpa, if (byte == '/') '\\' else byte);
                i += 2;
                continue;
            } else |_| {}
        }
        try out.append(gpa, if (b == '/') '\\' else b);
    }
    if (out.items.len == 0) {
        out.deinit(gpa);
        return null;
    }
    return .{ .path = try out.toOwnedSlice(gpa), .fragment = fragment };
}

/// The folder of a Windows path, without the trailing backslash.
pub fn folderOf(path: []const u8) []const u8 {
    const cut = std.mem.lastIndexOfAny(u8, path, "\\/") orelse return path;
    return path[0..cut];
}

/// The last part of a path ("a b.md").
pub fn fileName(path: []const u8) []const u8 {
    const cut = std.mem.lastIndexOfAny(u8, path, "\\/") orelse return path;
    return path[cut + 1 ..];
}

const testing = std.testing;
const note_prefix = "https://note.cadex.example/";

test "paths become addresses and come back" {
    const url = try fileUrl(testing.allocator, note_prefix, "C:\\notas\\a b#1.md");
    defer testing.allocator.free(url);
    try testing.expectEqualStrings("https://note.cadex.example/C:/notas/a%20b%231.md", url);
    const back = (try localPath(testing.allocator, note_prefix, url)).?;
    defer testing.allocator.free(back.path);
    try testing.expectEqualStrings("C:\\notas\\a b#1.md", back.path);
    try testing.expect(back.fragment == null);
}

test "non-ASCII is encoded as UTF-8 and the fragment is split off" {
    const url = try fileUrl(testing.allocator, note_prefix, "C:\\ção.md");
    defer testing.allocator.free(url);
    try testing.expectEqualStrings("https://note.cadex.example/C:/%C3%A7%C3%A3o.md", url);
    const back = (try localPath(testing.allocator, note_prefix, "https://note.cadex.example/C:/%C3%A7%C3%A3o.md#topo")).?;
    defer testing.allocator.free(back.path);
    try testing.expectEqualStrings("C:\\ção.md", back.path);
    try testing.expectEqualStrings("topo", back.fragment.?);
}

test "other addresses are not ours" {
    try testing.expect((try localPath(testing.allocator, note_prefix, "https://example.com/C:/a.md")) == null);
    try testing.expect((try localPath(testing.allocator, note_prefix, note_prefix)) == null);
}

test "folder and name of a path" {
    try testing.expectEqualStrings("C:\\a\\b", folderOf("C:\\a\\b\\c.mp4"));
    try testing.expectEqualStrings("c.mp4", fileName("C:\\a\\b\\c.mp4"));
}

test {
    @import("win32").refAllDeep(@This());
}
