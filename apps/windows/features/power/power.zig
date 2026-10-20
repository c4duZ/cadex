//! Keep-awake (docs/spec/power.md), the Mac's PowerController: off,
//! always, or only while a terminal runs a program. The system's own
//! request (SetThreadExecutionState), which Windows drops when the process
//! ends, so the computer is never left held. Closing the lid follows the
//! system's "lid close" option.

const std = @import("std");
const w = @import("win32");
pub const commands = @import("commands.zig");

const c = w.c;

pub const Mode = enum {
    off,
    always,
    running,

    /// settings.json's power.keepAwake ("off", "always", "running").
    pub fn parse(name: []const u8) Mode {
        return std.meta.stringToEnum(Mode, name) orelse .off;
    }
};

/// What the app gives: whether a terminal in any space runs a program,
/// and a call when the mode or the hold changed (the title bar's icon).
pub const Host = struct {
    context: *anyopaque,
    any_running: *const fn (context: *anyopaque) bool,
    changed: *const fn (context: *anyopaque) void,
};

pub const Power = struct {
    host: Host,
    mode: Mode = .off,
    /// Held now: always, or running with a program running.
    holding: bool = false,
    /// power.keepDisplayOn: the screen stays on too.
    keep_display_on: bool = false,

    pub fn set(self: *Power, mode: Mode) void {
        if (mode == self.mode) return;
        self.mode = mode;
        self.check(true);
    }

    pub fn setDisplay(self: *Power, on: bool) void {
        if (on == self.keep_display_on) return;
        self.keep_display_on = on;
        if (self.holding) self.apply();
    }

    /// Holds or releases as the mode and the terminals say now; the app
    /// calls it from its one-second poll.
    pub fn check(self: *Power, force: bool) void {
        const should = shouldHold(self.mode, self.mode == .running and self.host.any_running(self.host.context));
        if (!force and should == self.holding) return;
        self.holding = should;
        self.apply();
        self.host.changed(self.host.context);
    }

    fn apply(self: *Power) void {
        var flags: c.EXECUTION_STATE = c.ES_CONTINUOUS;
        if (self.holding) {
            flags |= c.ES_SYSTEM_REQUIRED;
            if (self.keep_display_on) flags |= c.ES_DISPLAY_REQUIRED;
        }
        // Refused: back to off, the icon as the outline (spec).
        if (c.SetThreadExecutionState(flags) == 0 and self.holding) {
            self.holding = false;
            if (self.mode == .always) self.mode = .off;
        }
    }
};

/// The rule, apart from Windows: always holds; running holds only with a
/// program running.
pub fn shouldHold(mode: Mode, any_running: bool) bool {
    return switch (mode) {
        .off => false,
        .always => true,
        .running => any_running,
    };
}

test "always holds; running only with a program; off never" {
    try std.testing.expect(shouldHold(.always, false));
    try std.testing.expect(shouldHold(.running, true));
    try std.testing.expect(!shouldHold(.running, false));
    try std.testing.expect(!shouldHold(.off, true));
    try std.testing.expectEqual(Mode.running, Mode.parse("running"));
    try std.testing.expectEqual(Mode.off, Mode.parse("forever"));
}

test {
    @import("win32").refAllDeep(@This());
}
