//! The documents' side of the app: the editor's and markdown's hosts, the
//! opener's makers for code and notes, the editor's colors from the theme,
//! and the opens that features ask for while a pane draws (a Ctrl+click in
//! a note, a file of a commit), which wait for the end of the frame: doing
//! them at once could free the document that is drawing.

const std = @import("std");
const w = @import("win32");
const cadex = @import("cadex");
const tabs = @import("tabs");
const editor = @import("editor");
const markdown = @import("markdown");
const palette = @import("command-palette");
const opener = @import("opener.zig");
const App = @import("app.zig").App;

fn of(context: *anyopaque) *App {
    return @ptrCast(@alignCast(context));
}

/// An open asked for during the frame, done after it.
pub const Deferred = union(enum) {
    file: struct { path: []u8, line: u32, how: opener.How },
    url: []u8,
    rendered: []u8,
    document: struct { doc: tabs.Document, how: palette.How },

    fn deinit(self: Deferred, gpa: std.mem.Allocator) void {
        switch (self) {
            .file => |f| gpa.free(f.path),
            .url, .rendered => |s| gpa.free(s),
            .document => {},
        }
    }
};

pub fn defer_(app: *App, item: Deferred) void {
    app.deferred.append(app.gpa, item) catch {
        if (item == .document) item.document.doc.destroy();
        item.deinit(app.gpa);
    };
    app.window.redraw();
}

/// After the frame: the opens asked for while it drew.
pub fn runDeferred(app: *App) void {
    if (app.deferred.items.len == 0) return;
    const items = app.deferred.toOwnedSlice(app.gpa) catch return;
    defer app.gpa.free(items);
    for (items) |item| {
        defer item.deinit(app.gpa);
        switch (item) {
            .file => |f| opener.open(app, f.path, f.line, f.how),
            .url => |u| opener.systemOpen(app, u),
            .rendered => |p| opener.openRendered(app, p),
            .document => |d| {
                app.tabs.open(d.doc, whereFor(app, d.how), null);
            },
        }
    }
    app.window.redraw();
}

pub fn whereFor(app: *App, how: palette.How) tabs.OpenFiles {
    return switch (how) {
        .beside => .beside,
        .new_tab => .tab,
        .normal => if (std.mem.eql(u8, app.settings.current.general.open_files, "tab")) .tab else .beside,
    };
}

pub fn deinit(app: *App) void {
    for (app.deferred.items) |item| {
        if (item == .document) item.document.doc.destroy();
        item.deinit(app.gpa);
    }
    app.deferred.deinit(app.gpa);
    app.markdown.deinit();
}

// ---- Editor and markdown ----

pub fn editorHost(app: *App) editor.Host {
    return .{ .context = app, .open_externally = openExternally, .focused_document = focusedDocument };
}

fn openExternally(context: *anyopaque, path: []const u8) void {
    opener.systemOpen(of(context), path);
}

pub fn focusedDocument(context: *anyopaque) ?tabs.Document {
    return of(context).tabs.focusedDocument();
}

pub fn markdownHost(app: *App) markdown.Host {
    return .{
        .context = app,
        .editor = editorHost(app),
        .open_file = openFile,
        .open_url = openUrl,
        .show_rendered = showRendered,
        .show_palette = showPalette,
    };
}

fn openFile(context: *anyopaque, path: []const u8, line: ?u32) void {
    const app = of(context);
    const copy = app.gpa.dupe(u8, path) catch return;
    defer_(app, .{ .file = .{ .path = copy, .line = line orelse 0, .how = .setting } });
}

fn openUrl(context: *anyopaque, url: []const u8) void {
    const app = of(context);
    defer_(app, .{ .url = app.gpa.dupe(u8, url) catch return });
}

fn showRendered(context: *anyopaque, path: []const u8) void {
    const app = of(context);
    defer_(app, .{ .rendered = app.gpa.dupe(u8, path) catch return });
}

fn showPalette(context: *anyopaque, source: palette.Source) void {
    const app = of(context);
    app.palette.toggle(&app.u, source);
}

/// The opener's makers for the kinds this file wires: code and notes.
pub fn register(app: *App) void {
    opener.makers.set(.code, makeCode);
    opener.makers.set(.markdown, makeNote);
    editor.commands.register(&app.registry, editorHost(app));
    markdown.commands.register(&app.registry, &app.markdown);
}

fn makeCode(app: *App, path: []const u8, line: u32) ?tabs.Document {
    const doc = editor.open(app.gpa, editorHost(app), path) catch return null;
    if (line > 0) editor.goToLine(doc, line);
    return doc;
}

fn makeNote(app: *App, path: []const u8, line: u32) ?tabs.Document {
    // markdown.openAs "rendered": the page, unless a line was asked for
    // (a search result, a link to a heading), which only the text has.
    if (line == 0 and std.mem.eql(u8, app.settings.current.markdown.open_as, "rendered")) {
        if (opener.rendered) |make| if (make(app, path, 0)) |doc| return doc;
    }
    const doc = app.markdown.open(path) catch return null;
    if (line > 0) editor.goToLine(doc, line);
    return doc;
}

/// The editor in the terminal's font and the theme's colors (the Mac's
/// EditorAppearance from the terminal theme).
pub fn applyTheme(app: *App) void {
    const s = app.settings.current.terminal;
    const t = app.themes.current.terminal;
    const font = app.term_font.get(s.font_family, @floatCast(s.font_size), app.window.scale());
    const secondary = app.u.style.secondary_text;
    editor.appearance.current = editor.Appearance.fromTerminal(.{
        .font_family = if (font) |f| f.family else "Cascadia Mono",
        .font_points = @floatCast(s.font_size),
        .background = t.background,
        .foreground = t.foreground,
        .selection = t.selection,
        .secondary_text = rgbOf(secondary.r, secondary.g, secondary.b),
        .ansi = t.ansi,
    });
}

fn rgbOf(r: f32, g: f32, b: f32) u32 {
    const byte = struct {
        fn channel(v: f32) u32 {
            return @intFromFloat(@round(std.math.clamp(v, 0, 1) * 255));
        }
    }.channel;
    return byte(r) << 16 | byte(g) << 8 | byte(b);
}

/// Folders changed on disk: the open editors and notes in them reload
/// (the editor compares with what it read and asks when there are edits).
pub fn diskChanged(app: *App, folders: []const []const u8) void {
    var docs: std.ArrayList(tabs.Document) = .empty;
    defer docs.deinit(app.gpa);
    for (app.spaces.list.items) |s| s.tabs.documents(&docs);
    for (docs.items) |d| {
        const path = editor.pathOf(d) orelse continue;
        const folder = std.fs.path.dirnameWindows(path) orelse continue;
        for (folders) |f| if (std.ascii.eqlIgnoreCase(std.mem.trimEnd(u8, f, "\\/"), folder)) {
            _ = editor.reload(d);
            break;
        };
    }
}

/// A saved pane's document (the spaces' restore): files that still exist
/// and the git history; diffs and previews were passing things. The
/// folder is authorized again, as the core forgets between launches (the
/// Mac's FileOpener.makeDocument, 2026-10-19).
pub fn makeSaved(app: *App, identity: []const u8) ?tabs.Document {
    const history = "history:";
    if (std.mem.startsWith(u8, identity, history)) return @import("git_page.zig").restoreHistory(app, identity[history.len..]);
    const folder = std.fs.path.dirnameWindows(identity) orelse return null;
    if (!exists(app, identity) or !authorize(app, folder)) return null;
    const make = opener.makers.get(opener.kindOf(identity)) orelse return null;
    return make(app, identity, 0);
}

pub fn exists(app: *App, path: []const u8) bool {
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(app.gpa, path) catch return false;
    defer app.gpa.free(wide);
    return w.c.GetFileAttributesW(wide.ptr) != w.c.INVALID_FILE_ATTRIBUTES;
}

pub fn authorize(app: *App, folder: []const u8) bool {
    const z = app.gpa.dupeZ(u8, folder) catch return false;
    defer app.gpa.free(z);
    var real: [*c]u8 = null;
    var len: usize = 0;
    if (cadex.cadex_workspace_authorize(z.ptr, &real, &len) != cadex.CADEX_OK) return false;
    cadex.cadex_free(real);
    return true;
}

test {
    w.refAllDeep(@This());
}
