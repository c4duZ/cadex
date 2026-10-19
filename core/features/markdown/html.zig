//! Markdown to HTML for the rendered view (docs/adr/0010-markdown-rendering.md):
//! md4c parses, this writes. Headings get GitHub anchors, code blocks the
//! editor's colors, `[[wiki]]` links a cadex-wiki: address the app resolves,
//! and raw HTML goes through the sanitizer.

const std = @import("std");
const md = @cImport(@cInclude("md4c.h"));
const anchor = @import("anchor.zig");
const Sanitizer = @import("sanitize.zig").Sanitizer;
const code = @import("code_html.zig");

const flags = md.MD_FLAG_TABLES | md.MD_FLAG_STRIKETHROUGH | md.MD_FLAG_TASKLISTS | md.MD_FLAG_WIKILINKS |
    md.MD_FLAG_PERMISSIVEURLAUTOLINKS | md.MD_FLAG_PERMISSIVEWWWAUTOLINKS;

/// The HTML body for `text` (UTF-8). Caller frees.
pub fn render(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    defer w.deinit();
    const parser: md.MD_PARSER = .{
        .abi_version = 0,
        .flags = flags,
        .enter_block = enterBlock,
        .leave_block = leaveBlock,
        .enter_span = enterSpan,
        .leave_span = leaveSpan,
        .text = onText,
        .debug_log = null,
        .syntax = null,
    };
    if (md.md_parse(text.ptr, @intCast(text.len), &parser, &w) != 0 or w.failed) return error.RenderFailed;
    return w.out.toOwnedSlice(gpa);
}

const Writer = struct {
    gpa: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,
    failed: bool = false,
    sanitizer: Sanitizer = .{},
    anchors: anchor.Counter = .{},
    /// While inside a heading: its HTML (written after the id is known)
    /// and its plain text (for the id).
    heading: ?struct { level: u32, html: std.ArrayList(u8), plain: std.ArrayList(u8) } = null,
    /// While inside a code block: its language and text, colored at the end.
    code_block: ?struct { lang: std.ArrayList(u8), text: std.ArrayList(u8) } = null,
    /// Inside an image: text goes to the alt attribute.
    image_depth: u32 = 0,

    fn deinit(self: *Writer) void {
        self.out.deinit(self.gpa);
        self.anchors.deinit(self.gpa);
        if (self.heading) |*h| {
            h.html.deinit(self.gpa);
            h.plain.deinit(self.gpa);
        }
        if (self.code_block) |*c| {
            c.lang.deinit(self.gpa);
            c.text.deinit(self.gpa);
        }
    }

    /// Where HTML goes now: the heading being built or the page.
    fn target(self: *Writer) *std.ArrayList(u8) {
        if (self.heading) |*h| return &h.html;
        return &self.out;
    }

    fn raw(self: *Writer, s: []const u8) void {
        self.target().appendSlice(self.gpa, s) catch {
            self.failed = true;
        };
    }

    fn escaped(self: *Writer, s: []const u8) void {
        escape(self.gpa, self.target(), s) catch {
            self.failed = true;
        };
    }
};

pub fn escape(gpa: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |ch| switch (ch) {
        '&' => try out.appendSlice(gpa, "&amp;"),
        '<' => try out.appendSlice(gpa, "&lt;"),
        '>' => try out.appendSlice(gpa, "&gt;"),
        '"' => try out.appendSlice(gpa, "&quot;"),
        else => try out.append(gpa, ch),
    };
}

fn attribute(a: md.MD_ATTRIBUTE) []const u8 {
    if (a.size == 0 or a.text == null) return "";
    return a.text[0..a.size];
}

fn writer(userdata: ?*anyopaque) *Writer {
    return @ptrCast(@alignCast(userdata.?));
}

fn enterBlock(kind: md.MD_BLOCKTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
    const w = writer(userdata);
    switch (kind) {
        md.MD_BLOCK_QUOTE => w.raw("<blockquote>\n"),
        md.MD_BLOCK_UL => w.raw("<ul>\n"),
        md.MD_BLOCK_OL => {
            const d: *md.MD_BLOCK_OL_DETAIL = @ptrCast(@alignCast(detail.?));
            if (d.start == 1) w.raw("<ol>\n") else {
                var buf: [32]u8 = undefined;
                w.raw(std.fmt.bufPrint(&buf, "<ol start=\"{d}\">\n", .{d.start}) catch "<ol>\n");
            }
        },
        md.MD_BLOCK_LI => {
            const d: *md.MD_BLOCK_LI_DETAIL = @ptrCast(@alignCast(detail.?));
            if (d.is_task != 0) {
                w.raw(if (d.task_mark == ' ') "<li class=\"task\"><input type=\"checkbox\" disabled> " else "<li class=\"task\"><input type=\"checkbox\" checked disabled> ");
            } else w.raw("<li>");
        },
        md.MD_BLOCK_HR => w.raw("<hr>\n"),
        md.MD_BLOCK_H => {
            const d: *md.MD_BLOCK_H_DETAIL = @ptrCast(@alignCast(detail.?));
            w.heading = .{ .level = d.level, .html = .empty, .plain = .empty };
        },
        md.MD_BLOCK_CODE => {
            const d: *md.MD_BLOCK_CODE_DETAIL = @ptrCast(@alignCast(detail.?));
            var lang: std.ArrayList(u8) = .empty;
            lang.appendSlice(w.gpa, attribute(d.lang)) catch {
                w.failed = true;
            };
            w.code_block = .{ .lang = lang, .text = .empty };
        },
        md.MD_BLOCK_P => w.raw("<p>"),
        md.MD_BLOCK_TABLE => w.raw("<table>\n"),
        md.MD_BLOCK_THEAD => w.raw("<thead>\n"),
        md.MD_BLOCK_TBODY => w.raw("<tbody>\n"),
        md.MD_BLOCK_TR => w.raw("<tr>"),
        md.MD_BLOCK_TH, md.MD_BLOCK_TD => {
            const d: *md.MD_BLOCK_TD_DETAIL = @ptrCast(@alignCast(detail.?));
            const tag = if (kind == md.MD_BLOCK_TH) "th" else "td";
            const style: []const u8 = switch (d.@"align") {
                md.MD_ALIGN_LEFT => " style=\"text-align:left\"",
                md.MD_ALIGN_CENTER => " style=\"text-align:center\"",
                md.MD_ALIGN_RIGHT => " style=\"text-align:right\"",
                else => "",
            };
            var buf: [48]u8 = undefined;
            w.raw(std.fmt.bufPrint(&buf, "<{s}{s}>", .{ tag, style }) catch "<td>");
        },
        else => {},
    }
    return 0;
}

fn leaveBlock(kind: md.MD_BLOCKTYPE, _: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
    const w = writer(userdata);
    switch (kind) {
        md.MD_BLOCK_QUOTE => w.raw("</blockquote>\n"),
        md.MD_BLOCK_UL => w.raw("</ul>\n"),
        md.MD_BLOCK_OL => w.raw("</ol>\n"),
        md.MD_BLOCK_LI => w.raw("</li>\n"),
        md.MD_BLOCK_H => finishHeading(w) catch {
            w.failed = true;
        },
        md.MD_BLOCK_CODE => finishCode(w) catch {
            w.failed = true;
        },
        md.MD_BLOCK_P => w.raw("</p>\n"),
        md.MD_BLOCK_TABLE => w.raw("</table>\n"),
        md.MD_BLOCK_THEAD => w.raw("</thead>\n"),
        md.MD_BLOCK_TBODY => w.raw("</tbody>\n"),
        md.MD_BLOCK_TR => w.raw("</tr>\n"),
        md.MD_BLOCK_TH => w.raw("</th>"),
        md.MD_BLOCK_TD => w.raw("</td>"),
        else => {},
    }
    return 0;
}

fn finishHeading(w: *Writer) !void {
    var h = w.heading orelse return;
    w.heading = null;
    defer {
        h.html.deinit(w.gpa);
        h.plain.deinit(w.gpa);
    }
    const id = try w.anchors.next(w.gpa, std.mem.trim(u8, h.plain.items, " "));
    defer w.gpa.free(id);
    var open: [16]u8 = undefined;
    try w.out.appendSlice(w.gpa, try std.fmt.bufPrint(&open, "<h{d} id=\"", .{h.level}));
    try escape(w.gpa, &w.out, id);
    try w.out.appendSlice(w.gpa, "\">");
    try w.out.appendSlice(w.gpa, h.html.items);
    try w.out.appendSlice(w.gpa, try std.fmt.bufPrint(&open, "</h{d}>\n", .{h.level}));
}

fn finishCode(w: *Writer) !void {
    var c = w.code_block orelse return;
    w.code_block = null;
    defer {
        c.lang.deinit(w.gpa);
        c.text.deinit(w.gpa);
    }
    try code.write(w.gpa, &w.out, c.lang.items, c.text.items);
}

fn enterSpan(kind: md.MD_SPANTYPE, detail: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
    const w = writer(userdata);
    if (w.image_depth > 0) {
        if (kind == md.MD_SPAN_IMG) w.image_depth += 1;
        return 0;
    }
    switch (kind) {
        md.MD_SPAN_EM => w.raw("<em>"),
        md.MD_SPAN_STRONG => w.raw("<strong>"),
        md.MD_SPAN_DEL => w.raw("<del>"),
        md.MD_SPAN_CODE => w.raw("<code>"),
        md.MD_SPAN_A => {
            const d: *md.MD_SPAN_A_DETAIL = @ptrCast(@alignCast(detail.?));
            w.raw("<a href=\"");
            w.escaped(attribute(d.href));
            if (attribute(d.title).len > 0) {
                w.raw("\" title=\"");
                w.escaped(attribute(d.title));
            }
            w.raw("\">");
        },
        md.MD_SPAN_IMG => {
            const d: *md.MD_SPAN_IMG_DETAIL = @ptrCast(@alignCast(detail.?));
            w.raw("<img src=\"");
            w.escaped(attribute(d.src));
            w.raw("\" alt=\"");
            w.image_depth = 1;
        },
        md.MD_SPAN_WIKILINK => {
            const d: *md.MD_SPAN_WIKILINK_DETAIL = @ptrCast(@alignCast(detail.?));
            w.raw("<a class=\"wiki\" href=\"cadex-wiki:");
            w.escaped(attribute(d.target));
            w.raw("\">");
        },
        else => {},
    }
    return 0;
}

fn leaveSpan(kind: md.MD_SPANTYPE, _: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) c_int {
    const w = writer(userdata);
    if (w.image_depth > 0) {
        if (kind == md.MD_SPAN_IMG) {
            w.image_depth -= 1;
            if (w.image_depth == 0) w.raw("\">");
        }
        return 0;
    }
    switch (kind) {
        md.MD_SPAN_EM => w.raw("</em>"),
        md.MD_SPAN_STRONG => w.raw("</strong>"),
        md.MD_SPAN_DEL => w.raw("</del>"),
        md.MD_SPAN_CODE => w.raw("</code>"),
        md.MD_SPAN_A, md.MD_SPAN_WIKILINK => w.raw("</a>"),
        else => {},
    }
    return 0;
}

fn onText(kind: md.MD_TEXTTYPE, text: [*c]const md.MD_CHAR, size: md.MD_SIZE, userdata: ?*anyopaque) callconv(.c) c_int {
    const w = writer(userdata);
    const s: []const u8 = if (size == 0) "" else text[0..size];
    if (w.code_block) |*c| {
        c.text.appendSlice(w.gpa, s) catch {
            w.failed = true;
        };
        return 0;
    }
    if (w.heading) |*h| if (kind != md.MD_TEXT_HTML) h.plain.appendSlice(w.gpa, s) catch {
        w.failed = true;
    };
    switch (kind) {
        md.MD_TEXT_NULLCHAR => w.raw("\u{FFFD}"),
        md.MD_TEXT_BR => w.raw(if (w.image_depth > 0) " " else "<br>\n"),
        md.MD_TEXT_SOFTBR => w.raw(if (w.image_depth > 0) " " else "\n"),
        md.MD_TEXT_HTML => if (w.image_depth == 0) {
            w.sanitizer.write(w.gpa, w.target(), s) catch {
                w.failed = true;
            };
        },
        // An entity as written (&amp;, &#169;): already valid HTML.
        md.MD_TEXT_ENTITY => w.raw(s),
        else => w.escaped(s),
    }
    return 0;
}

const testing = std.testing;

fn expectContains(html: []const u8, part: []const u8) !void {
    if (std.mem.indexOf(u8, html, part) == null) {
        std.debug.print("missing: {s}\nin: {s}\n", .{ part, html });
        return error.Missing;
    }
}

test "GitHub flavor: headings with anchors, tables, tasks, strikethrough, links" {
    const html = try render(testing.allocator,
        \\# Decisão Final
        \\
        \\| a | b |
        \\|:--|--:|
        \\| 1 | 2 |
        \\
        \\- [x] feito
        \\- [ ] falta
        \\
        \\~~velho~~ e [nota](outra.md#topo) e [[Ideias]] ![logo](img/a.png "t")
        \\
    );
    defer testing.allocator.free(html);
    try expectContains(html, "<h1 id=\"decisão-final\">Decisão Final</h1>");
    try expectContains(html, "<th style=\"text-align:left\">a</th>");
    try expectContains(html, "<li class=\"task\"><input type=\"checkbox\" checked disabled> feito</li>");
    try expectContains(html, "<del>velho</del>");
    try expectContains(html, "<a href=\"outra.md#topo\">nota</a>");
    try expectContains(html, "<a class=\"wiki\" href=\"cadex-wiki:Ideias\">Ideias</a>");
    try expectContains(html, "<img src=\"img/a.png\" alt=\"logo\">");
}

test "raw HTML is sanitized and text escaped" {
    const html = try render(testing.allocator, "<script>alert(1)</script>\n\nTexto <b onclick=\"x\">forte</b> & <i>.\n");
    defer testing.allocator.free(html);
    try testing.expect(std.mem.indexOf(u8, html, "<script") == null);
    try testing.expect(std.mem.indexOf(u8, html, "onclick") == null);
    try expectContains(html, "<b>forte</b> &amp;");
}

test "code blocks get the editor's colors" {
    const html = try render(testing.allocator, "```zig\nconst x = 1;\n```\n");
    defer testing.allocator.free(html);
    try expectContains(html, "<pre><code class=\"language-zig\"><span class=\"t1\">const</span>");
}
