//! The order of the tabs, which one is active, and the order of use
//! (docs/spec/tabs.md). Pure: ids only, the Mac's TabList.swift rules.

const std = @import("std");

pub const TabList = struct {
    gpa: std.mem.Allocator,
    order: std.ArrayList(u32) = .empty,
    active: ?u32 = null,
    /// Most recently used first; Ctrl+Tab goes back to the second.
    recent: std.ArrayList(u32) = .empty,

    pub fn deinit(self: *TabList) void {
        self.order.deinit(self.gpa);
        self.recent.deinit(self.gpa);
    }

    /// Adds a tab right after the active one and makes it active.
    pub fn insert(self: *TabList, id: u32) void {
        const at = if (self.active) |a| (if (std.mem.indexOfScalar(u32, self.order.items, a)) |i| i + 1 else self.order.items.len) else self.order.items.len;
        self.order.insert(self.gpa, at, id) catch return;
        self.select(id);
    }

    pub fn select(self: *TabList, id: u32) void {
        if (std.mem.indexOfScalar(u32, self.order.items, id) == null) return;
        self.active = id;
        if (std.mem.indexOfScalar(u32, self.recent.items, id)) |i| _ = self.recent.orderedRemove(i);
        self.recent.insert(self.gpa, 0, id) catch {};
    }

    /// Removes a tab. If it was active, the one used before it takes over.
    pub fn remove(self: *TabList, id: u32) void {
        if (std.mem.indexOfScalar(u32, self.order.items, id)) |i| _ = self.order.orderedRemove(i);
        if (std.mem.indexOfScalar(u32, self.recent.items, id)) |i| _ = self.recent.orderedRemove(i);
        if (self.active == id) {
            self.active = null;
            const next = if (self.recent.items.len > 0) self.recent.items[0] else if (self.order.items.len > 0) self.order.items[0] else return;
            self.select(next);
        }
    }

    /// The tab at a 1-based position (Ctrl+Shift+1 to 9), or null past the end.
    pub fn atPosition(self: *const TabList, position: usize) ?u32 {
        return if (position >= 1 and position <= self.order.items.len) self.order.items[position - 1] else null;
    }

    /// Ctrl+Tab: the tab used before the current one.
    pub fn previouslyUsed(self: *const TabList) ?u32 {
        return if (self.recent.items.len > 1) self.recent.items[1] else null;
    }

    /// Ctrl+Shift+Tab: the tab used longest ago.
    pub fn leastRecentlyUsed(self: *const TabList) ?u32 {
        return if (self.recent.items.len > 1) self.recent.items[self.recent.items.len - 1] else null;
    }

    /// Drag to reorder: puts the tab at `index` in the order.
    pub fn move(self: *TabList, id: u32, index: usize) void {
        const from = std.mem.indexOfScalar(u32, self.order.items, id) orelse return;
        _ = self.order.orderedRemove(from);
        self.order.insert(self.gpa, @min(index, self.order.items.len), id) catch {};
    }
};

/// The title of a tab from its folder: the last component, "~" for home.
pub fn folderTitle(path: ?[]const u8, home: ?[]const u8) []const u8 {
    const p = path orelse return "~";
    if (p.len == 0) return "~";
    if (home) |h| if (std.mem.eql(u8, std.mem.trimEnd(u8, p, "\\/"), std.mem.trimEnd(u8, h, "\\/"))) return "~";
    const trimmed = std.mem.trimEnd(u8, p, "\\/");
    const cut = std.mem.lastIndexOfAny(u8, trimmed, "\\/") orelse return trimmed;
    const name = trimmed[cut + 1 ..];
    return if (name.len == 0) p else name;
}

const testing = std.testing;

test "insert after the active one, select, remove back to the previous" {
    var l: TabList = .{ .gpa = testing.allocator };
    defer l.deinit();
    l.insert(1);
    l.insert(2);
    l.select(1);
    l.insert(3);
    try testing.expectEqualSlices(u32, &.{ 1, 3, 2 }, l.order.items);
    try testing.expectEqual(@as(?u32, 1), l.previouslyUsed());
    l.remove(3);
    try testing.expectEqual(@as(?u32, 1), l.active);
    try testing.expectEqual(@as(?u32, null), l.atPosition(5));
    l.move(2, 0);
    try testing.expectEqualSlices(u32, &.{ 2, 1 }, l.order.items);
}

test "folder titles" {
    try testing.expectEqualStrings("cadex", folderTitle("C:\\Users\\ana\\cadex", "C:\\Users\\ana"));
    try testing.expectEqualStrings("~", folderTitle("C:\\Users\\ana\\", "C:\\Users\\ana"));
    try testing.expectEqualStrings("~", folderTitle(null, null));
}
