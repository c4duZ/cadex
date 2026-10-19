//! Links as ⌘+hover sees them: built from a real frame, joined across
//! wrapped rows, and OSC 8 hyperlinks a program printed.

const std = @import("std");
const testing = std.testing;
const Model = @import("model.zig").Model;
const render = @import("render.zig");
const links = @import("links.zig");

const Fixture = struct {
    model: *Model,
    renderer: render.Renderer = .{},

    fn init(cols: u16) !Fixture {
        return .{ .model = try Model.create(testing.io, testing.allocator, .{ .cols = cols, .rows = 4 }) };
    }

    fn deinit(self: *Fixture) void {
        self.renderer.deinit(testing.allocator);
        self.model.destroy();
    }

    fn linkAt(self: *Fixture, col: u16, row: u16) !?links.Link {
        try self.renderer.capture(testing.allocator, &self.model.terminal, null);
        if (try links.hyperlinkAt(testing.allocator, &self.renderer.state, .{ .col = col, .row = row })) |l| {
            _ = try self.renderer.build(testing.allocator, null);
            return l;
        }
        _ = try self.renderer.build(testing.allocator, null);
        return links.detectAt(testing.allocator, &self.renderer, .{ .col = col, .row = row }, .{ .cwd = "/usr", .home = null });
    }
};

test "a URL split over two rows is one link" {
    var f = try Fixture.init(20);
    defer f.deinit();
    // 20 columns: "abra https://exemplo" / ".com/docs ok"
    f.model.feed("abra https://exemplo.com/docs ok");

    const link = (try f.linkAt(2, 1)).?;
    defer link.deinit(testing.allocator);
    try testing.expectEqual(links.Kind.url, link.kind);
    try testing.expectEqualStrings("https://exemplo.com/docs", link.target);
    try testing.expectEqual(links.Point{ .col = 5, .row = 0 }, link.start);
    try testing.expectEqual(links.Point{ .col = 8, .row = 1 }, link.end);

    try testing.expect(try f.linkAt(0, 0) == null);
}

test "an existing relative path resolves against the directory" {
    var f = try Fixture.init(30);
    defer f.deinit();
    f.model.feed("veja bin/ e nao/existe");

    const link = (try f.linkAt(6, 0)).?;
    defer link.deinit(testing.allocator);
    try testing.expectEqual(links.Kind.path, link.kind);
    try testing.expectEqualStrings("/usr/bin/", link.target);
    try testing.expect(try f.linkAt(14, 0) == null);
}

test "OSC 8 hyperlinks open their target, not their text" {
    var f = try Fixture.init(30);
    defer f.deinit();
    f.model.feed("ver \x1b]8;;https://cadex.dev/x\x1b\\o site\x1b]8;;\x1b\\ fim");

    const link = (try f.linkAt(5, 0)).?;
    defer link.deinit(testing.allocator);
    try testing.expectEqualStrings("https://cadex.dev/x", link.target);
    try testing.expectEqual(links.Point{ .col = 4, .row = 0 }, link.start);
    try testing.expectEqual(links.Point{ .col = 9, .row = 0 }, link.end);
}
