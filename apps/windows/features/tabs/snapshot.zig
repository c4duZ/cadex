//! The tabs as the spaces save them, in the JSON the Mac writes
//! (TabsSnapshot.swift, Swift's Codable shape): {"active": 0, "items":
//! [{"terminal": {"title": null, "focus": 1, "layout": {"split":
//! {"sideBySide": true, "ratio": 0.5, "first": {"pane": {"folder": ...}},
//! "second": {"document": {"identity": ...}}}}, "color": "red"}}]}, the
//! color only when the tab has one (plan 15). Not the terminals' content:
//! every pane starts a new shell (docs/spec/spaces.md).

const std = @import("std");
const controller = @import("controller.zig");
const pane_tree = @import("pane_tree.zig");
const tab_mod = @import("tab.zig");
const Document = @import("document.zig").Document;

const Tabs = controller.Tabs;
const Node = pane_tree.Node;

pub fn write(tabs: *Tabs, j: *std.json.Stringify) !void {
    var arena: std.heap.ArenaAllocator = .init(tabs.gpa);
    defer arena.deinit();
    try j.beginObject();
    try j.objectField("active");
    var active: ?usize = null;
    for (tabs.list.order.items, 0..) |id, i| if (tabs.list.active == id) {
        active = i;
    };
    try j.write(active);
    try j.objectField("items");
    try j.beginArray();
    for (tabs.list.order.items) |id| {
        const t = tabs.tabs.get(id) orelse continue;
        try j.beginObject();
        try j.objectField("terminal");
        try j.beginObject();
        try j.objectField("title");
        try j.write(t.name);
        try j.objectField("focus");
        var leaves: std.ArrayList(u32) = .empty;
        t.tree.leaves(&leaves);
        defer leaves.deinit(tabs.gpa);
        try j.write(std.mem.indexOfScalar(u32, leaves.items, t.focus) orelse 0);
        try j.objectField("layout");
        try layout(tabs, t, t.tree.root, j, arena.allocator());
        if (t.color) |name| {
            try j.objectField("color");
            try j.write(name);
        }
        try j.endObject();
        try j.endObject();
    }
    try j.endArray();
    try j.endObject();
}

fn layout(tabs: *Tabs, t: *tab_mod.Tab, node: *const Node, j: *std.json.Stringify, arena: std.mem.Allocator) !void {
    try j.beginObject();
    switch (node.*) {
        .leaf => |id| switch (t.panes.get(id).?) {
            .terminal => |v| {
                try j.objectField("pane");
                try j.beginObject();
                try j.objectField("folder");
                const dir = v.session.workingDirectory();
                defer if (dir) |d| d.free();
                try j.write(if (dir) |d| d.bytes else (tabs.host.home(tabs.host.context) orelse ""));
                try j.endObject();
            },
            .document => |d| {
                try j.objectField("document");
                try j.beginObject();
                try j.objectField("identity");
                try j.write(d.identity());
                try j.endObject();
            },
        },
        .split => |s| {
            try j.objectField("split");
            try j.beginObject();
            try j.objectField("sideBySide");
            try j.write(s.axis == .horizontal);
            try j.objectField("ratio");
            try j.write(s.ratio);
            try j.objectField("first");
            try layout(tabs, t, s.a, j, arena);
            try j.objectField("second");
            try layout(tabs, t, s.b, j, arena);
            try j.endObject();
        },
    }
    try j.endObject();
}

/// Makes a document again from its identity (the app knows every kind).
pub const MakeDocument = struct {
    context: *anyopaque,
    make: *const fn (context: *anyopaque, identity: []const u8) ?Document,
};

/// Rebuilds the tabs of a saved space: new shells in the saved folders, the
/// documents made by the app. A document gone from the disk, next to other
/// panes, becomes a terminal in its folder; a broken entry is skipped.
pub fn restore(tabs: *Tabs, value: std.json.Value, make_document: MakeDocument) void {
    if (value != .object) return;
    const items = value.object.get("items") orelse return;
    if (items != .array) return;
    var restored: std.ArrayList(u32) = .empty;
    defer restored.deinit(tabs.gpa);
    for (items.array.items) |item| {
        if (item != .object) continue;
        // The plan 7 form: a whole tab for one document.
        if (item.object.get("document")) |d| {
            if (d == .object) if (d.object.get("identity")) |id| if (id == .string) {
                if (make_document.make(make_document.context, id.string)) |doc| tabs.addTab(.{ .document = doc });
            };
            continue;
        }
        const term = item.object.get("terminal") orelse continue;
        if (term != .object) continue;
        const lay = term.object.get("layout") orelse continue;
        const before = tabs.list.order.items.len;
        restoreTab(tabs, lay, make_document);
        if (tabs.list.order.items.len == before) continue;
        const t = tabs.active().?;
        if (term.object.get("title")) |title| if (title == .string) t.setName(title.string);
        if (term.object.get("color")) |color| if (color == .string) t.setColor(color.string);
        if (term.object.get("focus")) |f| if (f == .integer) {
            var leaves: std.ArrayList(u32) = .empty;
            defer leaves.deinit(tabs.gpa);
            t.tree.leaves(&leaves);
            if (f.integer >= 0 and f.integer < leaves.items.len) t.focus = leaves.items[@intCast(f.integer)];
        };
        restored.append(tabs.gpa, t.id) catch {};
    }
    if (value.object.get("active")) |a| if (a == .integer and a.integer >= 0 and a.integer < restored.items.len) tabs.select(restored.items[@intCast(a.integer)]);
}

/// The first pane makes the tab; each split after it splits the pane on
/// its left (or above), so the tree comes back with the same shape.
fn restoreTab(tabs: *Tabs, lay: std.json.Value, make_document: MakeDocument) void {
    const first = firstLeaf(lay) orelse return;
    const pane = makePane(tabs, first, make_document) orelse return;
    tabs.addTab(pane);
    const t = tabs.active().?;
    grow(tabs, t, lay, t.focus, make_document);
    t.tree.balance();
    applyRatios(t.tree.root, lay);
}

fn firstLeaf(lay: std.json.Value) ?std.json.Value {
    if (lay != .object) return null;
    if (lay.object.get("split")) |s| {
        if (s != .object) return null;
        return firstLeaf(s.object.get("first") orelse return null);
    }
    return lay;
}

/// Adds the panes of `lay` after `at`, which already holds its first leaf.
fn grow(tabs: *Tabs, t: *tab_mod.Tab, lay: std.json.Value, at: u32, make_document: MakeDocument) void {
    const s = (lay.object.get("split") orelse return).object;
    const side_by_side = if (s.get("sideBySide")) |v| v == .bool and v.bool else true;
    const first = s.get("first") orelse return;
    const second = s.get("second") orelse return;
    const leaf = firstLeaf(second) orelse return;
    const pane = makePane(tabs, leaf, make_document) orelse return grow(tabs, t, first, at, make_document);
    t.focus = at;
    const id = tabs.next_pane;
    tabs.next_pane += 1;
    t.split(if (side_by_side) .horizontal else .vertical, id, pane) catch return pane.destroy(tabs.gpa);
    grow(tabs, t, first, at, make_document);
    grow(tabs, t, second, id, make_document);
}

fn makePane(tabs: *Tabs, leaf: std.json.Value, make_document: MakeDocument) ?tab_mod.Pane {
    if (leaf.object.get("pane")) |p| {
        const folder = if (p == .object) (if (p.object.get("folder")) |f| (if (f == .string) f.string else null) else null) else null;
        const view = tabs.host.make_terminal(tabs.host.context, folder) orelse return null;
        return .{ .terminal = view };
    }
    if (leaf.object.get("document")) |d| {
        const identity = if (d == .object) (if (d.object.get("identity")) |i| (if (i == .string) i.string else null) else null) else null;
        if (identity) |id| if (make_document.make(make_document.context, id)) |doc| return .{ .document = doc };
        const view = tabs.host.make_terminal(tabs.host.context, null) orelse return null;
        return .{ .terminal = view };
    }
    return null;
}

/// The saved proportions, where the shape matched; a hand-edited number
/// is kept between 0.1 and 0.9, as on the Mac.
fn applyRatios(node: *Node, lay: std.json.Value) void {
    if (node.* != .split or lay != .object) return;
    const s = (lay.object.get("split") orelse return);
    if (s != .object) return;
    if (s.object.get("ratio")) |r| {
        const ratio: f32 = switch (r) {
            .float => |f| @floatCast(f),
            .integer => |i| @floatFromInt(i),
            else => node.split.ratio,
        };
        node.split.ratio = std.math.clamp(ratio, 0.1, 0.9);
    }
    applyRatios(node.split.a, s.object.get("first") orelse return);
    applyRatios(node.split.b, s.object.get("second") orelse return);
}

test {
    @import("win32").refAllDeep(@This());
}
