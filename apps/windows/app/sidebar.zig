//! The sidebar (the Mac's SidebarView): the explorer's tree or the Git page,
//! switched by two tabs at the bottom, "Arquivos" and "Git" (they run the
//! explorer.focus and git.show commands); view.toggle-sidebar hides it.
//! Also the workspace following the focused terminal: a `cd` takes the tree
//! to the repository root of the new folder, or to the folder itself outside
//! one (the owner wants folders without .git in the tree, 2026-10-21; the
//! indexes stay light even on the home folder). Off with
//! explorer.followTerminal (docs/spec/workspace.md).

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const ui = @import("ui");
const icons = @import("icons");
const strings = @import("strings");
const explorer = @import("explorer");
const App = @import("app.zig").App;

pub const Page = enum { files, git };

pub const Sidebar = struct {
    visible: bool = true,
    page: Page = .files,
    /// The terminal folder last followed, to act only on a change.
    followed: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *Sidebar, gpa: std.mem.Allocator) void {
        self.followed.deinit(gpa);
    }
};

pub const width_dips = 240;

fn run(context: *anyopaque, id: []const u8) void {
    const app: *App = @ptrCast(@alignCast(context));
    _ = app.registry.run(id);
}

pub fn draw(app: *App, area: gfx.Rect) void {
    const u = &app.u;
    const radius = u.px(8);
    u.painter.fillRounded(area, radius, u.style.panel_border);
    const inner = area.inset(1, 1);
    u.painter.fillRounded(inner, radius, u.style.panel);
    var content = inner;
    const tabs_row = content.takeBottom(u.rowPx(34)).inset(u.px(6), u.px(4));
    const half = tabs_row.w / 2;
    const files_r: gfx.Rect = .{ .x = tabs_row.x, .y = tabs_row.y, .w = half - u.px(2), .h = tabs_row.h };
    const git_r: gfx.Rect = .{ .x = tabs_row.x + half + u.px(2), .y = tabs_row.y, .w = half - u.px(2), .h = tabs_row.h };
    if (ui.widgets.button(u, ui.id("sidebar.files", 0), files_r, strings.t("Files", "Arquivos"), .{ .icon = icons.phosphor.files, .icon_size = 14, .selected = app.sidebar.page == .files, .@"align" = .{ .@"align" = .center } })) _ = app.registry.run("explorer.focus");
    if (ui.widgets.button(u, ui.id("sidebar.git", 0), git_r, "Git", .{ .icon = icons.phosphor.git_branch, .icon_size = 14, .selected = app.sidebar.page == .git, .@"align" = .{ .@"align" = .center } })) {
        if (!app.registry.run("git.show")) app.sidebar.page = .git;
    }
    u.painter.pushClip(content);
    defer u.painter.popClip();
    switch (app.sidebar.page) {
        .files => {
            const result = explorer.view.draw(&app.explorer, u, content, run, app);
            if (result.dropped_outside) |paths| dropIntoTerminal(app, paths, result.at);
        },
        .git => @import("git_page.zig").draw(app, content),
    }
}

/// Rows dragged from the tree onto a terminal: their paths, escaped.
fn dropIntoTerminal(app: *App, paths: []const []const u8, at: gfx.Point) void {
    if (!app.panes_area.contains(at)) return;
    const view = app.tabs.focusedTerminal() orelse return;
    const quoted = @import("terminal").paste.quotePaths(app.gpa, paths) orelse return;
    defer app.gpa.free(quoted);
    view.session.write(quoted);
}

/// Called every frame: if the focused terminal moved to another folder,
/// the workspace follows it to that folder's repository root, or to the
/// folder itself outside a repository.
pub fn followTerminal(app: *App) void {
    const view = app.tabs.focusedTerminal() orelse return;
    const dir = view.session.workingDirectory() orelse return;
    defer dir.free();
    if (std.mem.eql(u8, dir.bytes, app.sidebar.followed.items)) return;
    app.sidebar.followed.clearRetainingCapacity();
    app.sidebar.followed.appendSlice(app.gpa, dir.bytes) catch return;
    var windows_buf: [2048]u8 = undefined;
    const folder = @import("environments.zig").windowsFolder(view, dir.bytes, &windows_buf);
    // Ctrl+Shift+P keeps the files nearest the terminal in a workspace too
    // big to index whole (docs/spec/search.md).
    app.search.setFocus(folder);
    if (!app.settings.current.explorer.follow_terminal) return;
    var buf: [2048]u8 = undefined;
    const repository = repositoryRoot(folder, &buf);
    const root = repository orelse folder;
    if (app.explorer.root()) |current| {
        // Inside the current project (cd src) the tree stays where it is;
        // outside a repository only the same folder does.
        const inside = std.ascii.startsWithIgnoreCase(root, current) and (root.len == current.len or root[current.len] == '\\');
        if (if (repository != null) inside else std.ascii.eqlIgnoreCase(root, current)) return;
    }
    setWorkspace(app, root);
}

pub fn setWorkspace(app: *App, folder: []const u8) void {
    const hidden = app.settings.current.explorer.show_hidden;
    app.explorer.setRoot(folder, hidden);
    const r = app.explorer.root() orelse return;
    app.search.setRoot(r, hidden);
    app.markdown.setRoot(r);
    @import("git_page.zig").setFolder(app, r);
}

/// The nearest folder at or above `folder` holding a `.git`, or null.
fn repositoryRoot(folder: []const u8, out: []u8) ?[]const u8 {
    var current = std.mem.trimEnd(u8, folder, "\\/");
    while (current.len > 0) {
        const probe = std.fmt.bufPrintZ(out, "{s}\\.git", .{current}) catch return null;
        var wide: [2048:0]u16 = undefined;
        const n = std.unicode.wtf8ToWtf16Le(&wide, probe) catch return null;
        wide[n] = 0;
        if (w.c.GetFileAttributesW(&wide) != w.c.INVALID_FILE_ATTRIBUTES) {
            @memcpy(out[0..current.len], current);
            return out[0..current.len];
        }
        const cut = std.mem.lastIndexOfAny(u8, current, "\\/") orelse return null;
        current = current[0..cut];
        if (current.len <= 2) return null;
    }
    return null;
}

test {
    w.refAllDeep(@This());
}
