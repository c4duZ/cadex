//! settings.json in %APPDATA%\Cadex: read at start, written on every change
//! from the app, and read again when edited by hand (polled once a second
//! by the window's timer), so a change counts at once (docs/spec/settings.md).

const std = @import("std");
const w = @import("win32");
const model = @import("model.zig");

pub const Store = struct {
    gpa: std.mem.Allocator,
    path: []u8,
    /// Holds the strings of `current`; replaced on each read.
    arena: std.heap.ArenaAllocator,
    current: model.Settings = .{},
    stamp: u64 = 0,

    pub fn init(gpa: std.mem.Allocator) !Store {
        var self: Store = .{ .gpa = gpa, .path = try w.files.appData(gpa, "settings.json"), .arena = .init(gpa) };
        self.reload();
        return self;
    }

    pub fn deinit(self: *Store) void {
        self.arena.deinit();
        self.gpa.free(self.path);
    }

    /// Without a file, the defaults; it is born on the first change.
    pub fn reload(self: *Store) void {
        _ = self.arena.reset(.retain_capacity);
        self.stamp = w.files.modified(self.gpa, self.path);
        const a = self.arena.allocator();
        const data = w.files.read(a, self.path, 4 * 1024 * 1024) orelse {
            self.current = .{};
            return;
        };
        const got = model.read(a, data);
        self.current = got.settings;
        for (got.problems) |p| std.log.warn("settings.json: {s}", .{p});
    }

    /// True when the file changed on disk since the last read (and reloads it).
    pub fn poll(self: *Store) bool {
        const now = w.files.modified(self.gpa, self.path);
        if (now == self.stamp) return false;
        self.reload();
        return true;
    }

    /// Saves `next` (the settings window changed something).
    pub fn save(self: *Store, next: model.Settings) void {
        const text = model.write(self.gpa, next) catch return;
        defer self.gpa.free(text);
        w.files.writeAtomic(self.gpa, self.path, text) catch |err| {
            std.log.warn("settings.json não foi salvo: {s}", .{@errorName(err)});
            return;
        };
        self.reload();
    }
};

test {
    std.testing.refAllDecls(@This());
}
