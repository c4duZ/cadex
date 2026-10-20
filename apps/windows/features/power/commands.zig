//! The power commands (ADR 0005), the Mac's ids and titles
//! (apps/macos/features/power/PowerCommands.swift). Each shows only when it
//! changes something; the title bar's menu runs the same ids.

const palette = @import("command-palette");
const strings = @import("strings");
const power = @import("power.zig");

var target: *power.Power = undefined;

fn toggle(_: ?*anyopaque) void {
    target.toggle();
}
fn keepAwake(_: ?*anyopaque) void {
    target.set(.always);
}
fn keepAwakeWhileRunning(_: ?*anyopaque) void {
    target.set(.running);
}
fn allowSleep(_: ?*anyopaque) void {
    target.set(.off);
}
fn notAlways(_: ?*anyopaque) bool {
    return target.mode != .always;
}
fn notRunning(_: ?*anyopaque) bool {
    return target.mode != .running;
}
fn notOff(_: ?*anyopaque) bool {
    return target.mode != .off;
}

pub fn register(registry: *palette.Registry, p: *power.Power) void {
    target = p;
    registry.add(.{ .id = "power.toggle", .title = strings.t("Toggle Keep Awake", "Ligar ou desligar o manter acordado"), .keywords = &.{ "caffeinate", "amphetamine", "acordado", "awake", "dormir", "sleep" }, .shortcut = "cmd+shift+a", .run = toggle });
    registry.add(.{ .id = "power.keep-awake", .title = strings.t("Keep the Computer Awake", "Manter o computador acordado"), .keywords = &.{ "caffeinate", "amphetamine", "dormir", "sleep", "energia" }, .run = keepAwake, .available = notAlways });
    registry.add(.{ .id = "power.keep-awake-while-running", .title = strings.t("Keep Awake While a Program Runs", "Manter acordado com programa rodando"), .keywords = &.{ "caffeinate", "amphetamine", "dormir", "sleep", "agente", "build" }, .run = keepAwakeWhileRunning, .available = notRunning });
    registry.add(.{ .id = "power.allow-sleep", .title = strings.t("Let the Computer Sleep", "Deixar o computador dormir"), .keywords = &.{ "caffeinate", "amphetamine", "dormir", "sleep", "desligar" }, .run = allowSleep, .available = notOff });
}
