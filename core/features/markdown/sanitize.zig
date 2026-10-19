//! Cleans the raw HTML a Markdown file carries before it reaches the
//! rendered view (docs/adr/0010-markdown-rendering.md): elements that run
//! or load things are dropped with their content, `on*` attributes and
//! `javascript:` URLs go. The view also runs without JavaScript; this is
//! the first of the two walls.

const std = @import("std");

/// Elements removed with everything inside them.
const dropped_with_content = [_][]const u8{ "script", "style", "iframe", "object", "embed", "noscript", "template", "svg", "math" };
/// Elements removed, content kept (it is just text).
const dropped_tags = [_][]const u8{ "form", "input", "button", "textarea", "select", "link", "meta", "base", "frame", "frameset" };

/// Raw HTML may come in pieces (one per line of an HTML block): the state
/// carries over between them.
pub const Sanitizer = struct {
    /// Inside a dropped element: its name, until the closing tag.
    skipping: ?[]const u8 = null,

    pub fn write(self: *Sanitizer, gpa: std.mem.Allocator, out: *std.ArrayList(u8), html: []const u8) !void {
        var i: usize = 0;
        while (i < html.len) {
            const lt = std.mem.indexOfScalarPos(u8, html, i, '<') orelse {
                if (self.skipping == null) try out.appendSlice(gpa, html[i..]);
                return;
            };
            if (self.skipping == null) try out.appendSlice(gpa, html[i..lt]);
            const gt = tagEnd(html, lt) orelse {
                // A tag cut between pieces: drop the rest, it is never valid
                // to pass half a tag.
                return;
            };
            try self.tag(gpa, out, html[lt .. gt + 1]);
            i = gt + 1;
        }
    }

    fn tag(self: *Sanitizer, gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
        const closing = text.len > 1 and text[1] == '/';
        const name = tagName(text);
        if (self.skipping) |skip| {
            if (closing and std.ascii.eqlIgnoreCase(name, skip)) self.skipping = null;
            return;
        }
        if (text.len > 1 and (text[1] == '!' or text[1] == '?')) {
            // Comments and declarations: harmless, kept only as comments.
            if (std.mem.startsWith(u8, text, "<!--")) try out.appendSlice(gpa, text);
            return;
        }
        for (dropped_with_content) |d| if (std.ascii.eqlIgnoreCase(name, d)) {
            if (!closing and !std.mem.endsWith(u8, text, "/>")) self.skipping = d;
            return;
        };
        for (dropped_tags) |d| if (std.ascii.eqlIgnoreCase(name, d)) return;
        if (closing) return out.appendSlice(gpa, text);
        try writeOpenTag(gpa, out, text, name);
    }
};

/// Index of the `>` closing the tag at `lt`, skipping quoted values.
fn tagEnd(html: []const u8, lt: usize) ?usize {
    var quote: u8 = 0;
    var i = lt + 1;
    while (i < html.len) : (i += 1) {
        const ch = html[i];
        if (quote != 0) {
            if (ch == quote) quote = 0;
        } else if (ch == '"' or ch == '\'') {
            quote = ch;
        } else if (ch == '>') {
            return i;
        }
    }
    return null;
}

fn tagName(text: []const u8) []const u8 {
    var i: usize = 1;
    if (i < text.len and text[i] == '/') i += 1;
    const start = i;
    while (i < text.len and (std.ascii.isAlphanumeric(text[i]) or text[i] == '-')) i += 1;
    return text[start..i];
}

/// `<name attr=...>` with the dangerous attributes left out.
fn writeOpenTag(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8, name: []const u8) !void {
    try out.append(gpa, '<');
    try out.appendSlice(gpa, name);
    var i: usize = 1 + name.len;
    const end = if (std.mem.endsWith(u8, text, "/>")) text.len - 2 else text.len - 1;
    while (i < end) {
        while (i < end and std.ascii.isWhitespace(text[i])) i += 1;
        const attr_start = i;
        while (i < end and !std.ascii.isWhitespace(text[i]) and text[i] != '=') i += 1;
        const attr = text[attr_start..i];
        if (attr.len == 0) {
            i += 1;
            continue;
        }
        var value: []const u8 = "";
        if (i < end and text[i] == '=') {
            i += 1;
            const v_start = i;
            if (i < end and (text[i] == '"' or text[i] == '\'')) {
                const q = text[i];
                i += 1;
                while (i < end and text[i] != q) i += 1;
                i = @min(i + 1, end);
            } else {
                while (i < end and !std.ascii.isWhitespace(text[i])) i += 1;
            }
            value = text[v_start..i];
        }
        if (allowed(attr, value)) {
            try out.append(gpa, ' ');
            try out.appendSlice(gpa, text[attr_start..i]);
        }
    }
    try out.appendSlice(gpa, if (std.mem.endsWith(u8, text, "/>")) " />" else ">");
}

fn allowed(attr: []const u8, value: []const u8) bool {
    if (attr.len > 2 and std.ascii.eqlIgnoreCase(attr[0..2], "on")) return false;
    if (std.ascii.eqlIgnoreCase(attr, "srcdoc") or std.ascii.eqlIgnoreCase(attr, "formaction")) return false;
    const unquoted = std.mem.trim(u8, value, "\"' \t");
    var compact: [16]u8 = undefined;
    var n: usize = 0;
    for (unquoted) |ch| {
        if (std.ascii.isWhitespace(ch) or ch < 0x20) continue;
        if (n == compact.len) break;
        compact[n] = std.ascii.toLower(ch);
        n += 1;
    }
    for ([_][]const u8{ "javascript:", "vbscript:", "data:text" }) |bad| {
        if (std.mem.startsWith(u8, compact[0..n], bad)) return false;
    }
    return true;
}

const testing = std.testing;

fn clean(html: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var s: Sanitizer = .{};
    try s.write(testing.allocator, &out, html);
    return out.toOwnedSlice(testing.allocator);
}

test "scripts, styles and handlers go; the rest stays" {
    const a = try clean("<p onclick=\"x()\" class=\"note\">hi<script>alert(1)</script> there</p>");
    defer testing.allocator.free(a);
    try testing.expectEqualStrings("<p class=\"note\">hi there</p>", a);
    const b = try clean("<a href=\"java\tscript:alert(1)\">x</a><img src=x onerror=alert(1) />");
    defer testing.allocator.free(b);
    try testing.expectEqualStrings("<a>x</a><img src=x />", b);
    const c = try clean("<details><summary>Mais</summary>texto</details><!-- nota -->");
    defer testing.allocator.free(c);
    try testing.expectEqualStrings("<details><summary>Mais</summary>texto</details><!-- nota -->", c);
}

test "a dropped element spread over pieces stays dropped" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    var s: Sanitizer = .{};
    try s.write(testing.allocator, &out, "<div>\n<style>\n");
    try s.write(testing.allocator, &out, "body { display: none }\n");
    try s.write(testing.allocator, &out, "</style>\nok</div>");
    try testing.expectEqualStrings("<div>\n\nok</div>", out.items);
}
