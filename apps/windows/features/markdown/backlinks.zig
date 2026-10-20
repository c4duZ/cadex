//! "Quem aponta pra cá" in the palette (markdown.backlinks): each note
//! linking to the current one, at the line of its link; choosing opens
//! it there (the Mac's BacklinksSource).

const std = @import("std");
const strings = @import("strings");
const icons = @import("icons");
const palette = @import("command-palette");
const index_mod = @import("index.zig");
const Markdown = @import("controller.zig").Markdown;

const Entry = struct { path: []const u8, rel: []const u8, line: u32 };

pub const Backlinks = struct {
    arena: std.heap.ArenaAllocator,
    entries: []const Entry = &.{},
    controller: ?*Markdown = null,

    pub fn init(gpa: std.mem.Allocator) Backlinks {
        return .{ .arena = .init(gpa) };
    }

    pub fn deinit(self: *Backlinks) void {
        self.arena.deinit();
    }

    /// The list for the next showing; the old one is gone.
    pub fn fill(self: *Backlinks, controller: *Markdown, places: []const index_mod.Place) void {
        _ = self.arena.reset(.retain_capacity);
        self.controller = controller;
        const a = self.arena.allocator();
        const out = a.alloc(Entry, places.len) catch {
            self.entries = &.{};
            return;
        };
        for (places, out) |p, *e| {
            const path = a.dupe(u8, p.path) catch "";
            e.* = .{ .path = path, .rel = controller.relative(a, path), .line = p.line };
        }
        self.entries = out;
    }

    pub fn source(self: *Backlinks) palette.Source {
        return .{
            .context = self,
            .placeholder = strings.t("Notes that link here", "Quem aponta para esta nota"),
            .empty_text = strings.t("No notes link here", "Nenhuma nota aponta para esta"),
            .icon = icons.phosphor.link,
            .search = search,
            .choose = choose,
        };
    }

    fn cast(context: *anyopaque) *Backlinks {
        return @ptrCast(@alignCast(context));
    }

    fn search(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(palette.Item)) ?[]const u8 {
        const self = cast(context);
        for (self.entries) |e| {
            if (query.len > 0 and std.ascii.indexOfIgnoreCase(e.rel, query) == null) continue;
            const id = std.fmt.allocPrint(arena, "{s}\t{d}", .{ e.path, e.line }) catch continue;
            const detail = std.fmt.allocPrint(arena, "{s} {d}", .{ strings.t("line", "linha"), e.line }) catch "";
            out.append(arena, .{ .id = id, .title = e.rel, .detail = detail, .icon = icons.phosphor.file_md }) catch break;
        }
        return std.fmt.allocPrint(arena, "{d} links", .{self.entries.len}) catch null;
    }

    fn choose(context: *anyopaque, id: []const u8, _: palette.How) void {
        const self = cast(context);
        const controller = self.controller orelse return;
        const tab = std.mem.lastIndexOfScalar(u8, id, '\t') orelse return;
        const line = std.fmt.parseInt(u32, id[tab + 1 ..], 10) catch 0;
        controller.host.open_file(controller.host.context, id[0..tab], if (line > 0) line else null);
    }
};

test {
    @import("win32").refAllDeep(@This());
}
