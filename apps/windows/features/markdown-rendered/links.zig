//! What a click in the rendered note means, the Mac's followRendered
//! (apps/macos/features/markdown/MarkdownController.swift): `[[Nota]]`
//! comes as cadex-wiki:Nota (the core's HTML), a relative link as an
//! address on the note's server (resolved by the page against the note),
//! the rest is for the system browser.

const std = @import("std");
const webview = @import("webview");

pub const origin = "https://note.cadex.example/";

pub const Link = union(enum) {
    /// A note by name, percent-decoded ("Ideias"), for cadex_markdown_resolve.
    wiki: []u8,
    /// A file, and the heading anchor after "#" if any.
    file: struct { path: []u8, fragment: ?[]u8 },
    /// http:, https:, mailto:...
    web: []u8,

    pub fn deinit(self: Link, gpa: std.mem.Allocator) void {
        switch (self) {
            .wiki => |n| gpa.free(n),
            .file => |f| {
                gpa.free(f.path);
                if (f.fragment) |x| gpa.free(x);
            },
            .web => |u| gpa.free(u),
        }
    }
};

/// Null for what goes nowhere (javascript:, file: typed in the note).
pub fn classify(gpa: std.mem.Allocator, url: []const u8) !?Link {
    if (std.ascii.startsWithIgnoreCase(url, "cadex-wiki:")) {
        return .{ .wiki = try percentDecode(gpa, url["cadex-wiki:".len..]) };
    }
    if (try webview.urls.localPath(gpa, origin, url)) |local| {
        errdefer gpa.free(local.path);
        const fragment = if (local.fragment) |f| try percentDecode(gpa, f) else null;
        return .{ .file = .{ .path = local.path, .fragment = fragment } };
    }
    for ([_][]const u8{ "http:", "https:", "mailto:" }) |scheme| {
        if (std.ascii.startsWithIgnoreCase(url, scheme)) return .{ .web = try gpa.dupe(u8, url) };
    }
    return null;
}

fn percentDecode(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '%' and i + 2 < text.len) {
            if (std.fmt.parseInt(u8, text[i + 1 .. i + 3], 16)) |b| {
                try out.append(gpa, b);
                i += 2;
                continue;
            } else |_| {}
        }
        try out.append(gpa, text[i]);
    }
    return out.toOwnedSlice(gpa);
}

const testing = std.testing;

test "wiki links, files with headings and the web" {
    const gpa = testing.allocator;
    const wiki = (try classify(gpa, "cadex-wiki:Minhas%20Ideias")).?;
    defer wiki.deinit(gpa);
    try testing.expectEqualStrings("Minhas Ideias", wiki.wiki);

    const file = (try classify(gpa, "https://note.cadex.example/C:/notas/outra.md#t%C3%B3pico")).?;
    defer file.deinit(gpa);
    try testing.expectEqualStrings("C:\\notas\\outra.md", file.file.path);
    try testing.expectEqualStrings("tópico", file.file.fragment.?);

    const web = (try classify(gpa, "https://example.com/x")).?;
    defer web.deinit(gpa);
    try testing.expectEqualStrings("https://example.com/x", web.web);

    try testing.expect((try classify(gpa, "javascript:alert(1)")) == null);
    try testing.expect((try classify(gpa, "file:///C:/Windows/win.ini")) == null);
}

test {
    @import("win32").refAllDeep(@This());
}
