//! Reading settings.json field by field: a field of the wrong type keeps
//! its default and becomes a problem for the log (in Portuguese, as the
//! Mac's FieldReader writes them), the rest of the file still counts.

const std = @import("std");

pub const Reader = struct {
    arena: std.mem.Allocator,
    problems: std.ArrayList([]const u8) = .empty,

    pub fn note(self: *Reader, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.allocPrint(self.arena, fmt, args) catch return;
        self.problems.append(self.arena, text) catch {};
    }

    pub fn section(self: *Reader, root: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
        const value = root.get(key) orelse return null;
        if (value != .object) {
            self.note("{s}: esperava uma seção", .{key});
            return null;
        }
        return value.object;
    }

    pub fn string(self: *Reader, object: std.json.ObjectMap, group: []const u8, key: []const u8) ?[]const u8 {
        const value = object.get(key) orelse return null;
        if (value != .string) {
            self.note("{s}.{s}: esperava um texto", .{ group, key });
            return null;
        }
        return value.string;
    }

    pub fn boolean(self: *Reader, object: std.json.ObjectMap, group: []const u8, key: []const u8) ?bool {
        const value = object.get(key) orelse return null;
        if (value != .bool) {
            self.note("{s}.{s}: esperava true ou false", .{ group, key });
            return null;
        }
        return value.bool;
    }

    pub fn number(self: *Reader, object: std.json.ObjectMap, group: []const u8, key: []const u8) ?f64 {
        const value = object.get(key) orelse return null;
        return switch (value) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            else => {
                self.note("{s}.{s}: esperava um número", .{ group, key });
                return null;
            },
        };
    }

    pub fn strings(self: *Reader, object: std.json.ObjectMap, group: []const u8, key: []const u8) ?[]const []const u8 {
        const value = object.get(key) orelse return null;
        if (value == .array) {
            var list: std.ArrayList([]const u8) = .empty;
            for (value.array.items) |item| {
                if (item != .string) break;
                list.append(self.arena, item.string) catch return null;
            } else return list.items;
        }
        self.note("{s}.{s}: esperava uma lista de textos", .{ group, key });
        return null;
    }

    pub fn choice(self: *Reader, object: std.json.ObjectMap, group: []const u8, key: []const u8, options: []const []const u8) ?[]const u8 {
        const text = self.string(object, group, key) orelse return null;
        for (options) |o| if (std.mem.eql(u8, o, text)) return o;
        self.note("{s}.{s}: \"{s}\" não é uma das opções", .{ group, key, text });
        return null;
    }
};
