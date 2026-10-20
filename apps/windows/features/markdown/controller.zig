//! The notes of the workspace (docs/spec/markdown.md): the core's index, a
//! note open as an editable editor pane with the Markdown help attached
//! (session.zig), following links, the suggestions, and "Quem aponta pra
//! cá" as a palette list (the Mac's MarkdownController).

const std = @import("std");
const w = @import("win32");
const editor = @import("editor");
const tabs = @import("tabs");
const palette = @import("command-palette");
const index_mod = @import("index.zig");
const trigger = @import("trigger.zig");
const completion_mod = @import("completion.zig");
const Session = @import("session.zig").Session;
const Backlinks = @import("backlinks.zig").Backlinks;

/// What the markdown feature needs from the app. The callbacks may run
/// while a pane draws (a Ctrl+click, the "Visualizar" button): the app
/// changes the panes after the frame, as it does for the palette.
pub const Host = struct {
    context: *anyopaque,
    /// The notes are editor panes: the editor's host.
    editor: editor.Host,
    /// Opens a file in the Cadex, at a 1-based line when known (a link to a heading).
    open_file: *const fn (context: *anyopaque, path: []const u8, line: ?u32) void,
    /// A web link, in the browser.
    open_url: *const fn (context: *anyopaque, url: []const u8) void,
    /// markdown.toggle-preview: the rendered page of the note at `path`.
    show_rendered: *const fn (context: *anyopaque, path: []const u8) void,
    /// Shows a list in the palette ("Quem aponta pra cá").
    show_palette: *const fn (context: *anyopaque, source: palette.Source) void,
    /// The workspace's files matching `query`, best first, relative to the
    /// root with `/`, in `arena` (the search feature's file search), for
    /// `](`. Null: the notes only.
    find_files: ?*const fn (context: *anyopaque, arena: std.mem.Allocator, query: []const u8) []const []const u8 = null,
};

pub const Markdown = struct {
    gpa: std.mem.Allocator,
    host: Host,
    index: index_mod.Index = .{},
    /// The workspace root, absolute; null until the app sets it.
    root: ?[]u8 = null,
    /// For the "Visualizar" button, which runs the command by id (ADR 0005).
    registry: ?*palette.Registry = null,
    backlinks: Backlinks,

    pub fn init(gpa: std.mem.Allocator, host: Host) Markdown {
        return .{ .gpa = gpa, .host = host, .backlinks = .init(gpa) };
    }

    pub fn deinit(self: *Markdown) void {
        self.index.close();
        if (self.root) |r| self.gpa.free(r);
        self.backlinks.deinit();
    }

    /// The workspace folder changed: index its notes.
    pub fn setRoot(self: *Markdown, root: []const u8) void {
        if (self.root) |r| {
            if (std.mem.eql(u8, r, root)) return;
            self.gpa.free(r);
        }
        self.root = self.gpa.dupe(u8, root) catch null;
        if (self.root) |r| self.index.open(self.gpa, r);
    }

    pub fn isMarkdown(path: []const u8) bool {
        const ext = std.fs.path.extension(path);
        return std.ascii.eqlIgnoreCase(ext, ".md") or std.ascii.eqlIgnoreCase(ext, ".markdown");
    }

    /// A note in an editable editor pane, with the Markdown help.
    pub fn open(self: *Markdown, path: []const u8) !tabs.Document {
        const e = try editor.Editor.create(self.gpa, self.host.editor, path, .{ .editable = true });
        errdefer e.destroy();
        const session = try Session.create(self, e);
        e.setHooks(session.hooks());
        return e.document();
    }

    /// The note session of a document, when it is a note open here.
    pub fn sessionOf(doc: tabs.Document) ?*Session {
        const e = editor.Editor.of(doc) orelse return null;
        return Session.of(e);
    }

    /// The path relative to the root, with `/` (as links are written).
    pub fn relative(self: *const Markdown, arena: std.mem.Allocator, path: []const u8) []const u8 {
        var rel = path;
        if (self.root) |r| if (path.len > r.len + 1 and std.ascii.startsWithIgnoreCase(path, r)) {
            rel = path[r.len + 1 ..];
        };
        const copy = arena.dupe(u8, rel) catch return rel;
        std.mem.replaceScalar(u8, copy, '\\', '/');
        return copy;
    }

    /// A path relative to the root (with `/`) made absolute, in the system's form.
    pub fn absolute(self: *const Markdown, arena: std.mem.Allocator, rel: []const u8) []const u8 {
        const r = self.root orelse return rel;
        const joined = std.mem.concat(arena, u8, &.{ r, std.fs.path.sep_str, rel }) catch return rel;
        if (std.fs.path.sep == '\\') std.mem.replaceScalar(u8, joined, '/', '\\');
        return joined;
    }

    /// markdown.toggle-preview: the rendered page is its own document.
    pub fn togglePreview(self: *Markdown, path: []const u8) void {
        self.host.show_rendered(self.host.context, path);
    }

    /// The button runs the command, so it is the same action as the keys.
    pub fn runToggle(self: *Markdown, path: []const u8) void {
        if (self.registry) |r| if (r.run("markdown.toggle-preview")) return;
        self.togglePreview(path);
    }

    /// markdown.backlinks: the notes linking to `path`, in the palette.
    pub fn showBacklinks(self: *Markdown, path: []const u8) void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const places = self.index.backlinks(arena.allocator(), path);
        self.backlinks.fill(self, places);
        self.host.show_palette(self.host.context, self.backlinks.source());
    }

    pub fn follow(self: *Markdown, link: index_mod.Link) void {
        if (link.isWeb()) return self.host.open_url(self.host.context, link.target);
        if (link.target.len == 0 or (link.broken and !exists(self.gpa, link.target))) {
            _ = w.c.MessageBeep(0);
            return;
        }
        self.host.open_file(self.host.context, link.target, if (link.line > 0) link.line else null);
    }

    /// What the trigger offers, in `arena` (the Mac's suggestions(for:from:)).
    pub fn suggestions(self: *Markdown, arena: std.mem.Allocator, t: trigger.Trigger, note: []const u8) []const completion_mod.Item {
        var list: std.ArrayList(completion_mod.Item) = .empty;
        switch (t.what) {
            .path => for (self.files(arena, t.query)) |p| {
                const insert = trigger.relativePath(arena, p, note) catch continue;
                list.append(arena, .{ .title = std.fs.path.basenamePosix(p), .detail = p, .insert = insert }) catch break;
            },
            .heading => {
                const target = if (t.file.len == 0) note else trigger.normalize(arena, std.mem.concat(arena, u8, &.{ std.fs.path.dirnamePosix(note) orelse "", "/", t.file }) catch return &.{}) catch return &.{};
                for (self.index.headings(arena, self.absolute(arena, target))) |h| {
                    if (t.query.len > 0 and std.ascii.indexOfIgnoreCase(h.text, t.query) == null and std.ascii.indexOfIgnoreCase(h.anchor, t.query) == null) continue;
                    const detail = std.mem.concat(arena, u8, &.{ "#", h.anchor }) catch continue;
                    list.append(arena, .{ .title = h.text, .detail = detail, .insert = h.anchor, .icon = @import("icons").phosphor.link }) catch break;
                }
            },
            .note => for (self.index.notes(arena)) |p| {
                const base = std.fs.path.basenamePosix(p);
                if (t.query.len > 0 and std.ascii.indexOfIgnoreCase(base, t.query) == null) continue;
                const name = base[0 .. base.len - std.fs.path.extension(base).len];
                const insert = std.mem.concat(arena, u8, &.{ name, "]]" }) catch continue;
                list.append(arena, .{ .title = name, .detail = p, .insert = insert }) catch break;
                if (list.items.len == 30) break;
            },
        }
        return list.items;
    }

    /// Files for `](`: the app's file search, or the notes ranked by the core.
    fn files(self: *Markdown, arena: std.mem.Allocator, query: []const u8) []const []const u8 {
        if (self.host.find_files) |f| {
            const found = f(self.host.context, arena, query);
            return found[0..@min(found.len, 30)];
        }
        const notes = self.index.notes(arena);
        if (query.len == 0) return notes[0..@min(notes.len, 30)];
        const ranked = palette.rank(arena, query, notes) catch return &.{};
        const out = arena.alloc([]const u8, @min(ranked.len, 30)) catch return &.{};
        for (out, 0..) |*o, i| o.* = notes[ranked[i].index];
        return out;
    }
};

fn exists(gpa: std.mem.Allocator, path: []const u8) bool {
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(gpa, path) catch return false;
    defer gpa.free(wide);
    return w.c.GetFileAttributesW(wide.ptr) != w.c.INVALID_FILE_ATTRIBUTES;
}

test "notes are told by their extension" {
    try std.testing.expect(Markdown.isMarkdown("docs/README.md"));
    try std.testing.expect(Markdown.isMarkdown("a.MARKDOWN"));
    try std.testing.expect(!Markdown.isMarkdown("a.zig"));
}

test {
    @import("win32").refAllDeep(@This());
}
