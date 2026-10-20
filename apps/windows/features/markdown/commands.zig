//! The markdown commands (ADR 0005), the Mac's ids, titles and keys
//! (apps/macos/features/markdown/MarkdownCommands.swift), on the note with
//! the keyboard.

const palette = @import("command-palette");
const Markdown = @import("controller.zig").Markdown;
const Session = @import("session.zig").Session;

var markdown: *Markdown = undefined;

fn note() ?*Session {
    const doc = markdown.host.editor.focused_document(markdown.host.editor.context) orelse return null;
    return Markdown.sessionOf(doc);
}

fn hasNote(_: ?*anyopaque) bool {
    return note() != null;
}

fn togglePreview(_: ?*anyopaque) void {
    if (note()) |s| markdown.togglePreview(s.path());
}

fn openLink(_: ?*anyopaque) void {
    const s = note() orelse return;
    const view = s.editor.view() orelse return;
    _ = s.follow(view, view.buffer.caret);
}

fn backlinks(_: ?*anyopaque) void {
    if (note()) |s| markdown.showBacklinks(s.path());
}

pub fn register(registry: *palette.Registry, controller: *Markdown) void {
    markdown = controller;
    controller.registry = registry;
    registry.add(.{ .id = "markdown.toggle-preview", .title = "Alternar Markdown renderizado", .keywords = &.{ "preview", "renderizar", "visualizar" }, .shortcut = "cmd+shift+v", .run = togglePreview, .available = hasNote });
    registry.add(.{ .id = "markdown.open-link", .title = "Abrir o link sob o cursor", .keywords = &.{ "link", "seguir", "ir" }, .run = openLink, .available = hasNote });
    registry.add(.{ .id = "markdown.backlinks", .title = "Quem aponta pra cá", .keywords = &.{ "backlinks", "referências", "links" }, .run = backlinks, .available = hasNote });
}

test {
    @import("win32").refAllDeep(@This());
}
