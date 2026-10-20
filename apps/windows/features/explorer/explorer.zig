//! The explorer feature (docs/spec/explorer.md, docs/spec/workspace.md): the
//! workspace's tree in the sidebar, read through the core, following the
//! disk, with the Mac's commands. The workspace folder lives here too: the
//! root, authorized in the core whenever it changes.

const std = @import("std");
const ui = @import("ui");
const cadex = @import("cadex");
const palette = @import("command-palette");
const tree_mod = @import("tree.zig");
const watcher_mod = @import("watcher.zig");

pub const Tree = tree_mod.Tree;
pub const Node = tree_mod.Node;
pub const view = @import("view.zig");
pub const actions = @import("actions.zig");
pub const commands = @import("commands.zig");
pub const expanded_store = @import("expanded_store.zig");

pub const OpenHow = enum { setting, beside, tab };

/// What the explorer needs from the app.
pub const Host = struct {
    context: *anyopaque,
    /// Opens a file in the Cadex (by the "Abrir arquivos" setting, or as asked).
    open_file: *const fn (context: *anyopaque, path: []const u8, how: OpenHow) void,
    /// `cd` of the focused terminal into `folder` (explorer.open-in-terminal).
    open_in_terminal: *const fn (context: *anyopaque, folder: []const u8) void,
    /// The focused terminal's folder, copied into `out` (workspace.use-terminal-folder).
    terminal_folder: *const fn (context: *anyopaque, out: []u8) ?[]const u8,
    /// The git letter of a changed file ('M', 'A', 'U', 'D') from source control, or 0.
    git_mark: ?*const fn (context: *anyopaque, path: []const u8) u8 = null,
    /// From the watcher's thread: wake the window (PostMessage).
    wake: *const fn (context: *anyopaque) void,
    /// Folders changed on disk (open documents may reload).
    folders_changed: ?*const fn (context: *anyopaque, paths: []const []const u8) void = null,
};

pub const Explorer = struct {
    gpa: std.mem.Allocator,
    host: Host,
    tree: ?Tree = null,
    watcher: watcher_mod.Watcher,
    /// Paths of the selected rows, the last clicked first.
    selection: std.ArrayList([]u8) = .empty,
    /// Copied with explorer.copy-files, pasted with explorer.paste-files.
    copied: std.ArrayList([]u8) = .empty,
    scroll: ui.list.Scroll = .{},
    /// The row being renamed (its path) and the field.
    renaming: ?[]u8 = null,
    rename_text: ui.TextBuffer = .{},
    rename_scroll: ui.text_field.Scroll = .{},
    menu: ui.menu.Menu = .{},
    /// A short message under the tree ("Nome já usado").
    message: std.ArrayList(u8) = .empty,
    focus_id: ui.Id = ui.id("explorer.tree", 0),
    launched_with_folder: bool = false,

    pub fn init(gpa: std.mem.Allocator, host: Host) Explorer {
        return .{ .gpa = gpa, .host = host, .watcher = .{ .gpa = gpa, .wake = host.wake, .wake_context = host.context } };
    }

    pub fn deinit(self: *Explorer) void {
        self.saveExpanded();
        self.watcher.deinit();
        if (self.tree) |*t| t.deinit();
        self.clearSelection();
        self.selection.deinit(self.gpa);
        for (self.copied.items) |p| self.gpa.free(p);
        self.copied.deinit(self.gpa);
        if (self.renaming) |r| self.gpa.free(r);
        self.rename_text.deinit(self.gpa);
        self.message.deinit(self.gpa);
    }

    pub fn root(self: *const Explorer) ?[]const u8 {
        return if (self.tree) |t| t.root.path else null;
    }

    /// Makes `folder` the workspace: authorized in the core, the tree's
    /// root, watched. The open folders of this root come back.
    pub fn setRoot(self: *Explorer, folder: []const u8, show_hidden: bool) void {
        const z = self.gpa.dupeZ(u8, folder) catch return;
        defer self.gpa.free(z);
        var real: [*c]u8 = null;
        var len: usize = 0;
        if (cadex.cadex_workspace_authorize(z.ptr, &real, &len) != cadex.CADEX_OK) return;
        defer cadex.cadex_free(real);
        const canonical = real[0..len];
        if (self.root()) |r| if (std.ascii.eqlIgnoreCase(r, canonical)) return;
        self.saveExpanded();
        if (self.tree) |*t| t.deinit();
        self.tree = Tree.init(self.gpa, canonical) catch null;
        if (self.tree) |*t| {
            t.show_hidden = show_hidden;
            var arena: std.heap.ArenaAllocator = .init(self.gpa);
            defer arena.deinit();
            t.expandPaths(expanded_store.load(arena.allocator(), canonical));
        }
        self.clearSelection();
        self.scroll = .{};
        self.watcher.start(canonical);
    }

    fn saveExpanded(self: *Explorer) void {
        const t = &(self.tree orelse return);
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const paths = t.expandedPaths(arena.allocator()) catch return;
        expanded_store.save(self.gpa, t.root.path, paths);
    }

    pub fn setShowHidden(self: *Explorer, show: bool) void {
        const t = &(self.tree orelse return);
        if (t.show_hidden == show) return;
        t.show_hidden = show;
        t.reload(&.{}, true);
    }

    /// On the window's thread: reloads what the watcher saw change.
    pub fn drain(self: *Explorer) bool {
        const batch = self.watcher.drain() orelse return false;
        defer batch.deinit(self.gpa);
        if (self.tree) |*t| t.reload(batch.paths, batch.everything);
        if (self.host.folders_changed) |f| f(self.host.context, @ptrCast(batch.paths));
        return true;
    }

    pub fn clearSelection(self: *Explorer) void {
        for (self.selection.items) |p| self.gpa.free(p);
        self.selection.clearRetainingCapacity();
    }

    pub fn select(self: *Explorer, path: []const u8, extend: bool) void {
        if (!extend) self.clearSelection();
        for (self.selection.items, 0..) |p, i| if (std.mem.eql(u8, p, path)) {
            if (extend) {
                self.gpa.free(self.selection.orderedRemove(i));
                return;
            }
            return;
        };
        const copy = self.gpa.dupe(u8, path) catch return;
        self.selection.insert(self.gpa, 0, copy) catch self.gpa.free(copy);
    }

    pub fn isSelected(self: *const Explorer, path: []const u8) bool {
        for (self.selection.items) |p| if (std.mem.eql(u8, p, path)) return true;
        return false;
    }

    /// The node of the last selected row, if it is still in the tree.
    pub fn selectedNode(self: *Explorer) ?*Node {
        const t = &(self.tree orelse return null);
        if (self.selection.items.len == 0) return null;
        return t.find(self.selection.items[0]);
    }

    pub fn say(self: *Explorer, message: []const u8) void {
        self.message.clearRetainingCapacity();
        self.message.appendSlice(self.gpa, message) catch {};
    }

    /// Registers the explorer's and the workspace's commands.
    pub fn register(self: *Explorer, registry: *palette.Registry, with: commands.Wiring) void {
        commands.registerWith(self, registry, with);
    }
};

test {
    _ = @import("tree.zig");
    _ = @import("watcher.zig");
    _ = @import("view.zig");
    _ = @import("actions.zig");
    _ = @import("commands.zig");
    _ = @import("expanded_store.zig");
    @import("win32").refAllDeep(@This());
}
