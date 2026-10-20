//! The media commands (ADR 0005), the Mac's ids, titles and keys
//! (apps/macos/features/media-preview/MediaCommands.swift): the zoom of the
//! image in the focused pane. A PDF zooms with Edge's viewer itself (its
//! Ctrl+= and Ctrl+-), so here they are available only for images, and the
//! keys reach the PDF when the app asks registry.isAvailable first.

const palette = @import("command-palette");
const strings = @import("strings");
const tabs = @import("tabs");
const Media = @import("document.zig").Media;

pub const Current = struct {
    context: *anyopaque,
    /// The document of the focused pane, if it is not a terminal.
    focused: *const fn (context: *anyopaque) ?tabs.Document,
};

var current: Current = undefined;

fn active() ?*Media {
    const doc = current.focused(current.context) orelse return null;
    const m = Media.of(doc) orelse return null;
    return if (m.zoomable()) m else null;
}

fn zoomable(_: ?*anyopaque) bool {
    return active() != null;
}

fn zoomIn(_: ?*anyopaque) void {
    if (active()) |m| m.zoomIn();
}
fn zoomOut(_: ?*anyopaque) void {
    if (active()) |m| m.zoomOut();
}
fn zoomFit(_: ?*anyopaque) void {
    if (active()) |m| m.zoomToFit();
}
fn zoomActual(_: ?*anyopaque) void {
    if (active()) |m| m.actualSize();
}

pub fn register(registry: *palette.Registry, where: Current) void {
    current = where;
    registry.add(.{ .id = "media.zoom-in", .title = strings.t("Zoom In", "Aumentar o zoom"), .keywords = &.{ "zoom", "ampliar", "bigger" }, .shortcut = "cmd+=", .run = zoomIn, .available = zoomable });
    registry.add(.{ .id = "media.zoom-out", .title = strings.t("Zoom Out", "Diminuir o zoom"), .keywords = &.{ "zoom", "reduzir", "smaller" }, .shortcut = "cmd+-", .run = zoomOut, .available = zoomable });
    registry.add(.{ .id = "media.zoom-fit", .title = strings.t("Zoom to Fit", "Ajustar à aba"), .keywords = &.{ "zoom", "fit", "caber" }, .shortcut = "cmd+0", .run = zoomFit, .available = zoomable });
    registry.add(.{ .id = "media.zoom-actual", .title = strings.t("Actual Size", "Tamanho real"), .keywords = &.{ "zoom", "100%", "original" }, .shortcut = "cmd+opt+0", .run = zoomActual, .available = zoomable });
}

test {
    @import("win32").refAllDeep(@This());
}
