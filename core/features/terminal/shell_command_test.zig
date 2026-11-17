//! The shell's command from OSC 133, fed through the model as the zsh integration sends it.

const std = @import("std");
const model_file = @import("model.zig");
const Model = model_file.Model;
const Notice = model_file.Notice;
const testing = std.testing;

test "OSC 133 C with cmdline_url starts a command, D with the code ends it, each a title notice" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();
    const Capture = struct {
        var titles: usize = 0;
        fn notice(_: ?*anyopaque, n: Notice) void {
            if (n == .title) titles += 1;
        }
    };
    Capture.titles = 0;
    model.setNotice(&Capture.notice);
    model.feed("\x1b]133;C;cmdline_url=npm%20run%20dev%3B%20echo%20%C3%A9\x07");
    try testing.expect(model.command.running);
    try testing.expectEqualStrings("npm run dev; echo é", model.command.current());
    model.feed("\x1b]133;D;1\x07");
    try testing.expect(!model.command.running);
    try testing.expectEqual(@as(?i32, 1), model.command.last_exit);
    try testing.expectEqualStrings("npm run dev; echo é", model.command.previous());
    try testing.expectEqual(@as(usize, 2), Capture.titles);
}
