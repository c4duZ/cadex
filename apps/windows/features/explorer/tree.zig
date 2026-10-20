//! The tree's model (docs/spec/explorer.md): nodes read folder by folder
//! through the core only when opened, folders first in natural order (the
//! core sorts), notes for an empty folder or one without permission, and a
//! reload that keeps open folders and reuses unchanged nodes. The rows on
//! screen are the open part flattened, with compact folders (a folder
//! holding only one folder shows as "src/main/java").

const std = @import("std");
const cadex = @import("cadex");

pub const Kind = enum(u8) { file = 0, directory = 1, symlink = 2, other = 3 };

pub const Note = enum { none, empty, no_permission };

pub const Node = struct {
    /// Full path, owned.
    path: []u8,
    /// The last component of `path`.
    name: []const u8,
    kind: Kind,
    link_to_directory: bool = false,
    ignored: bool = false,
    size: u64 = 0,
    expanded: bool = false,
    /// Read since it was opened (children are valid).
    loaded: bool = false,
    note: Note = .none,
    children: std.ArrayList(*Node) = .empty,

    pub fn isFolder(self: *const Node) bool {
        return self.kind == .directory or self.link_to_directory;
    }

    fn destroy(self: *Node, gpa: std.mem.Allocator) void {
        for (self.children.items) |child| child.destroy(gpa);
        self.children.deinit(gpa);
        gpa.free(self.path);
        gpa.destroy(self);
    }
};

/// One line on screen: a node (the last folder of a compact chain), its
/// depth, and the label ("src/main/java" for a chain).
pub const Row = struct {
    node: *Node,
    depth: u16,
    label: []const u8,
    /// A note line under a folder ("Pasta vazia"), not a node of its own.
    note: Note = .none,
};

pub const Tree = struct {
    gpa: std.mem.Allocator,
    root: *Node,
    show_hidden: bool = true,

    pub fn init(gpa: std.mem.Allocator, root_path: []const u8) !Tree {
        const root = try newNode(gpa, root_path, .directory);
        root.expanded = true;
        var self: Tree = .{ .gpa = gpa, .root = root };
        self.load(root);
        return self;
    }

    pub fn deinit(self: *Tree) void {
        self.root.destroy(self.gpa);
    }

    fn newNode(gpa: std.mem.Allocator, path: []const u8, kind: Kind) !*Node {
        const node = try gpa.create(Node);
        errdefer gpa.destroy(node);
        const owned = try gpa.dupe(u8, std.mem.trimEnd(u8, path, "\\/"));
        node.* = .{ .path = owned, .name = baseName(owned), .kind = kind };
        return node;
    }

    /// Reads `node`'s folder from the core; children seen before keep their
    /// state (open, loaded), the rest are new, the gone ones freed.
    pub fn load(self: *Tree, node: *Node) void {
        const z = self.gpa.dupeZ(u8, node.path) catch return;
        defer self.gpa.free(z);
        var listing: cadex.cadex_explorer_listing = undefined;
        const status = cadex.cadex_explorer_list(z.ptr, &listing);
        node.loaded = true;
        if (status != cadex.CADEX_OK) {
            node.note = .no_permission;
            return;
        }
        defer cadex.cadex_explorer_listing_free(&listing);
        var next: std.ArrayList(*Node) = .empty;
        for (listing.entries[0..listing.count]) |e| {
            const name = listing.names[e.name_offset..][0..e.name_len];
            if (!self.show_hidden and name.len > 0 and name[0] == '.') continue;
            const kept = takeChild(node, name);
            const child = kept orelse blk: {
                const path = std.fmt.allocPrint(self.gpa, "{s}\\{s}", .{ node.path, name }) catch continue;
                defer self.gpa.free(path);
                break :blk newNode(self.gpa, path, @enumFromInt(e.kind)) catch continue;
            };
            child.kind = @enumFromInt(e.kind);
            child.link_to_directory = e.link_to_directory;
            child.ignored = e.ignored;
            child.size = e.size;
            next.append(self.gpa, child) catch child.destroy(self.gpa);
        }
        for (node.children.items) |gone| gone.destroy(self.gpa);
        node.children.deinit(self.gpa);
        node.children = next;
        node.note = if (next.items.len == 0) .empty else .none;
    }

    fn takeChild(node: *Node, name: []const u8) ?*Node {
        for (node.children.items, 0..) |child, i| {
            if (std.mem.eql(u8, child.name, name)) {
                _ = node.children.swapRemove(i);
                return child;
            }
        }
        return null;
    }

    pub fn toggle(self: *Tree, node: *Node) void {
        if (!node.isFolder()) return;
        node.expanded = !node.expanded;
        if (node.expanded and !node.loaded) self.load(node);
    }

    /// Reads again the loaded folders whose paths changed on disk (or all,
    /// with `everything`), keeping what is open.
    pub fn reload(self: *Tree, changed: []const []const u8, everything: bool) void {
        self.reloadNode(self.root, changed, everything);
    }

    fn reloadNode(self: *Tree, node: *Node, changed: []const []const u8, everything: bool) void {
        if (!node.loaded) return;
        var hit = everything;
        for (changed) |c| if (std.ascii.eqlIgnoreCase(std.mem.trimEnd(u8, c, "\\/"), node.path)) {
            hit = true;
        };
        if (hit) self.load(node);
        for (node.children.items) |child| if (child.expanded or child.loaded) self.reloadNode(child, changed, everything);
    }

    pub fn collapseAll(self: *Tree) void {
        collapse(self.root);
        self.root.expanded = true;
    }

    fn collapse(node: *Node) void {
        node.expanded = false;
        for (node.children.items) |child| collapse(child);
    }

    /// The open part of the tree as lines, in `arena`.
    pub fn rows(self: *Tree, arena: std.mem.Allocator) ![]Row {
        var out: std.ArrayList(Row) = .empty;
        try self.flatten(arena, self.root, 0, &out);
        return out.items;
    }

    fn flatten(self: *Tree, arena: std.mem.Allocator, node: *Node, depth: u16, out: *std.ArrayList(Row)) !void {
        for (node.children.items) |child| {
            var tail = child;
            var label: []const u8 = child.name;
            // A folder holding only one folder joins it on one line.
            while (tail.isFolder() and tail.kind == .directory) {
                if (!tail.loaded) self.load(tail);
                if (tail.children.items.len != 1 or !tail.children.items[0].isFolder() or tail.children.items[0].kind != .directory) break;
                tail = tail.children.items[0];
                label = try std.fmt.allocPrint(arena, "{s}/{s}", .{ label, tail.name });
            }
            try out.append(arena, .{ .node = tail, .depth = depth, .label = label });
            if (tail.expanded) {
                if (tail.note != .none) try out.append(arena, .{ .node = tail, .depth = depth + 1, .label = "", .note = tail.note });
                try self.flatten(arena, tail, depth + 1, out);
            }
        }
    }

    pub fn find(self: *Tree, path: []const u8) ?*Node {
        return findIn(self.root, path);
    }

    fn findIn(node: *Node, path: []const u8) ?*Node {
        if (std.ascii.eqlIgnoreCase(node.path, path)) return node;
        for (node.children.items) |child| {
            if (path.len > child.path.len and std.ascii.startsWithIgnoreCase(path, child.path) and (path[child.path.len] == '\\' or path[child.path.len] == '/')) return findIn(child, path);
            if (std.ascii.eqlIgnoreCase(child.path, path)) return child;
        }
        return null;
    }

    /// The paths of the open folders, to remember per root.
    pub fn expandedPaths(self: *Tree, arena: std.mem.Allocator) ![]const []const u8 {
        var out: std.ArrayList([]const u8) = .empty;
        try collectExpanded(self.root, arena, &out);
        return out.items;
    }

    fn collectExpanded(node: *Node, arena: std.mem.Allocator, out: *std.ArrayList([]const u8)) !void {
        for (node.children.items) |child| if (child.expanded) {
            try out.append(arena, child.path);
            try collectExpanded(child, arena, out);
        };
    }

    /// Opens the remembered folders that still exist (shallow first).
    pub fn expandPaths(self: *Tree, paths: []const []const u8) void {
        for (paths) |p| if (self.find(p)) |node| if (node.isFolder() and !node.expanded) self.toggle(node);
    }
};

pub fn baseName(path: []const u8) []const u8 {
    const trimmed = std.mem.trimEnd(u8, path, "\\/");
    const cut = std.mem.lastIndexOfAny(u8, trimmed, "\\/") orelse return trimmed;
    return trimmed[cut + 1 ..];
}

test "base names on Windows paths" {
    try std.testing.expectEqualStrings("cadex", baseName("C:\\code\\cadex\\"));
    try std.testing.expectEqualStrings("C:", baseName("C:"));
}

test {
    @import("win32").refAllDeep(@This());
}
