//! One tab: its tree of panes, what each pane holds (a terminal or a
//! document), the focused pane, and the name the user gave it.

const std = @import("std");
const terminal = @import("terminal");
const pane_tree = @import("pane_tree.zig");
const Document = @import("document.zig").Document;

pub const Pane = union(enum) {
    terminal: *terminal.View,
    document: Document,

    pub fn destroy(self: Pane, gpa: std.mem.Allocator) void {
        switch (self) {
            .terminal => |v| {
                v.deinit();
                gpa.destroy(v);
            },
            .document => |d| d.destroy(),
        }
    }
};

pub const Tab = struct {
    gpa: std.mem.Allocator,
    id: u32,
    tree: pane_tree.Tree,
    panes: std.AutoArrayHashMapUnmanaged(u32, Pane) = .empty,
    focus: u32,
    /// Set by renaming; null shows the focused pane's folder or title.
    name: ?[]u8 = null,

    pub fn init(gpa: std.mem.Allocator, id: u32, pane_id: u32, pane: Pane) !*Tab {
        const self = try gpa.create(Tab);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .id = id, .tree = try .init(gpa, pane_id), .focus = pane_id };
        try self.panes.put(gpa, pane_id, pane);
        return self;
    }

    pub fn deinit(self: *Tab) void {
        for (self.panes.values()) |p| p.destroy(self.gpa);
        self.panes.deinit(self.gpa);
        self.tree.deinit();
        if (self.name) |n| self.gpa.free(n);
        self.gpa.destroy(self);
    }

    pub fn focused(self: *Tab) Pane {
        return self.panes.get(self.focus).?;
    }

    pub fn setName(self: *Tab, name: []const u8) void {
        if (self.name) |n| self.gpa.free(n);
        const trimmed = std.mem.trim(u8, name, " ");
        // An empty name goes back to the folder's (docs/spec/tabs.md).
        self.name = if (trimmed.len == 0) null else self.gpa.dupe(u8, trimmed) catch null;
    }

    /// Splits the focused pane; the new one gets the focus.
    pub fn split(self: *Tab, axis: pane_tree.Axis, pane_id: u32, pane: Pane) !void {
        try self.panes.put(self.gpa, pane_id, pane);
        errdefer _ = self.panes.swapRemove(pane_id);
        try self.tree.split(self.focus, axis, pane_id);
        self.tree.balance();
        self.focus = pane_id;
    }

    /// Takes a pane out (its owner destroys it); false when it was the last.
    pub fn remove(self: *Tab, pane_id: u32) bool {
        if (!self.tree.remove(pane_id)) return false;
        _ = self.panes.orderedRemove(pane_id);
        self.tree.balance();
        if (self.focus == pane_id) {
            var leaves: std.ArrayList(u32) = .empty;
            defer leaves.deinit(self.gpa);
            self.tree.leaves(&leaves);
            self.focus = leaves.items[0];
        }
        return true;
    }

    /// Whether any pane is a document with unsaved changes ("●" in the title).
    pub fn unsaved(self: *Tab) bool {
        for (self.panes.values()) |p| switch (p) {
            .document => |d| if (d.unsaved()) return true,
            .terminal => {},
        };
        return false;
    }

    /// The document pane of the tab, if it has one (for "open beside").
    pub fn documentPane(self: *Tab) ?u32 {
        for (self.panes.keys(), self.panes.values()) |id, p| if (p == .document) return id;
        return null;
    }
};

test {
    @import("win32").refAllDeep(@This());
}
