//! The Markdown help of one note open in the editor (the Mac's
//! MarkdownSession): links checked a moment after typing stops, broken
//! ones underlined in red, Ctrl+click follows a link, suggestions while
//! writing `](`, `](file#` and `[[`, Enter continuing a list, and the
//! "Visualizar" button. Talks to the editor through its Hooks only.

const std = @import("std");
const strings = @import("strings");
const gfx = @import("gfx");
const w = @import("win32");
const ui_mod = @import("ui");
const icons = @import("icons");
const editor = @import("editor");
const index_mod = @import("index.zig");
const trigger = @import("trigger.zig");
const lists = @import("lists.zig");
const completion_mod = @import("completion.zig");
const Markdown = @import("controller.zig").Markdown;

const Ui = ui_mod.Ui;

/// Links are checked this long after the last key, not per key.
const settle_ms = 400;
const broken_red = gfx.Color.rgb(0xff453a);

/// A link of the text, in bytes, with what the core said of it.
const Link = struct { start: usize, end: usize, info: index_mod.Link };

pub const Session = struct {
    gpa: std.mem.Allocator,
    controller: *Markdown,
    editor: *editor.Editor,
    links_arena: std.heap.ArenaAllocator,
    links: []const Link = &.{},
    underlines: std.ArrayList(editor.Underline) = .empty,
    /// The text changed since the links were checked; when it did.
    links_stale: bool = true,
    stale_since: ?i64 = null,
    /// Links checked before the index's first read look broken: again once ready.
    checked_ready: bool = false,
    completion: completion_mod.Completion,
    /// The text changed or the caret moved: look at the trigger again.
    completion_stale: bool = false,
    /// Escape or a choice hides the list until the text changes again.
    dismissed_version: ?u64 = null,
    /// What the shown list was made for.
    shown_key: u64 = 0,

    pub fn create(controller: *Markdown, e: *editor.Editor) !*Session {
        const gpa = controller.gpa;
        const self = try gpa.create(Session);
        self.* = .{ .gpa = gpa, .controller = controller, .editor = e, .links_arena = .init(gpa), .completion = .init(gpa) };
        return self;
    }

    fn destroy(self: *Session) void {
        self.links_arena.deinit();
        self.underlines.deinit(self.gpa);
        self.completion.deinit();
        self.gpa.destroy(self);
    }

    pub fn hooks(self: *Session) editor.Hooks {
        return .{
            .context = self,
            .keys = keysHook,
            .changed = changedHook,
            .ctrl_click = ctrlClickHook,
            .underlines = underlinesHook,
            .overlay = overlayHook,
            .closed = closedHook,
        };
    }

    /// The session behind an editor, when it is a note open here.
    pub fn of(e: *editor.Editor) ?*Session {
        const h = e.hooks orelse return null;
        const k = h.keys orelse return null;
        if (k != &keysHook) return null;
        return @ptrCast(@alignCast(h.context));
    }

    fn cast(context: *anyopaque) *Session {
        return @ptrCast(@alignCast(context));
    }

    pub fn path(self: *const Session) []const u8 {
        return self.editor.path;
    }

    // ---- Links ----

    pub fn refreshLinks(self: *Session, view: *editor.View) void {
        _ = self.links_arena.reset(.retain_capacity);
        const arena = self.links_arena.allocator();
        const text = view.text();
        // Asked before the links: that query starts the (lazy) index, and a
        // small workspace is read before a later look, leaving links
        // checked too early (2026-10-20).
        const ready_before = self.controller.index.ready();
        const found = self.controller.index.links(arena, self.path(), text);
        const out = arena.alloc(Link, found.len) catch return;
        var walker: trigger.Utf16Walker = .{ .text = text };
        self.underlines.clearRetainingCapacity();
        for (found, out) |info, *l| {
            const start = walker.byteAt(info.start);
            l.* = .{ .start = start, .end = walker.byteAt(info.end), .info = info };
            if (info.broken) self.underlines.append(self.gpa, .{ .start = l.start, .end = l.end, .color = broken_red }) catch {};
        }
        self.links = out;
        self.links_stale = false;
        self.stale_since = null;
        self.checked_ready = ready_before;
    }

    fn linkAt(self: *const Session, at: usize) ?Link {
        for (self.links) |l| if (at >= l.start and at <= l.end) return l;
        return null;
    }

    /// Ctrl+click and markdown.open-link at the caret; false off a link.
    pub fn follow(self: *Session, view: *editor.View, at: usize) bool {
        self.refreshLinks(view);
        const l = self.linkAt(at) orelse return false;
        self.controller.follow(l.info);
        return true;
    }

    // ---- Suggestions ----

    fn updateCompletion(self: *Session, view: *editor.View) void {
        self.completion_stale = false;
        const b = &view.buffer;
        const found = if (b.hasSelection()) null else trigger.detect(b.text(), b.caret);
        const t = found orelse return self.completion.hide();
        if (self.dismissed_version == b.version) return;
        self.dismissed_version = null;
        const key = std.hash.Wyhash.hash(@as(u64, t.start) << 2 | @intFromEnum(t.what), t.query);
        if (self.completion.visible() and key == self.shown_key) return;
        self.shown_key = key;
        const arena = self.completion.begin();
        const note = self.controller.relative(arena, self.path());
        self.completion.items = self.controller.suggestions(arena, t, note);
    }

    fn choose(self: *Session, view: *editor.View, item: completion_mod.Item) void {
        const t = trigger.detect(view.text(), view.buffer.caret) orelse return self.completion.hide();
        // The item lives in the completion's arena, which hide() resets.
        const insert = self.gpa.dupe(u8, item.insert) catch return;
        defer self.gpa.free(insert);
        self.completion.hide();
        view.replaceRange(t.start, t.end, insert);
        self.dismissed_version = view.buffer.version;
    }

    /// Enter in a list item: the next item, or the end of the list.
    fn continueList(view: *editor.View, u: *Ui) void {
        const b = &view.buffer;
        if (b.hasSelection()) return;
        const line_start = b.lineStart(b.lineOf(b.caret));
        const c = lists.continuation(b.text()[line_start..b.caret]) orelse return;
        if (!u.key(w.c.VK_RETURN, .{})) return;
        switch (c) {
            .next => |n| {
                var value: [40]u8 = undefined;
                value[0] = '\n';
                @memcpy(value[1..][0..n.marker_len], n.marker[0..n.marker_len]);
                b.insert(value[0 .. n.marker_len + 1], .other) catch {};
            },
            .end => |len| view.replaceRange(line_start, line_start + len, ""),
        }
        view.reveal_caret = true;
    }

    // ---- Hooks ----

    fn keysHook(context: *anyopaque, u: *Ui, view: *editor.View) void {
        const self = cast(context);
        const was_visible = self.completion.visible();
        if (self.completion.keys(u)) |item| return self.choose(view, item);
        if (was_visible and !self.completion.visible()) self.dismissed_version = view.buffer.version;
        if (!self.completion.visible()) continueList(view, u);
        // Arrows and clicks move the caret: the list follows it.
        if (self.completion.visible()) self.completion_stale = true;
    }

    fn changedHook(context: *anyopaque, _: *editor.View) void {
        const self = cast(context);
        self.links_stale = true;
        self.stale_since = null;
        self.completion_stale = true;
    }

    fn ctrlClickHook(context: *anyopaque, view: *editor.View, at: usize) bool {
        return cast(context).follow(view, at);
    }

    fn underlinesHook(context: *anyopaque) []const editor.Underline {
        return cast(context).underlines.items;
    }

    fn overlayHook(context: *anyopaque, u: *Ui, view: *editor.View, area: gfx.Rect) void {
        const self = cast(context);
        self.settleLinks(u, view);
        if (u.focus != view.id) {
            self.completion.hide();
        } else if (self.completion_stale or self.completion.visible()) {
            self.updateCompletion(view);
        }
        if (self.completion.draw(u, ui_mod.child(view.id, 0xc0), view.caretRect(), area)) |item| self.choose(view, item);
        self.drawToggle(u, view, area);
    }

    fn closedHook(context: *anyopaque) void {
        cast(context).destroy();
    }

    /// Checks the links once typing has settled, and again when the index
    /// finishes its first read.
    fn settleLinks(self: *Session, u: *Ui, view: *editor.View) void {
        if (!self.checked_ready and self.controller.index.ready()) self.links_stale = true;
        if (!self.checked_ready and !self.controller.index.ready()) u.requestFrame(300);
        if (!self.links_stale) return;
        const since = self.stale_since orelse blk: {
            self.stale_since = u.now_ms;
            // The first check of a note opened is at once.
            if (self.links.len == 0 and view.buffer.history.undo_list.items.len == 0) {
                self.refreshLinks(view);
                return;
            }
            break :blk u.now_ms;
        };
        const waited = u.now_ms - since;
        if (waited >= settle_ms) self.refreshLinks(view) else u.requestFrame(@intCast(settle_ms - waited));
    }

    /// "Visualizar" at the top right, which runs markdown.toggle-preview.
    /// Without it nobody found the rendered view (owner, 2026-10-19).
    fn drawToggle(self: *Session, u: *Ui, view: *editor.View, area: gfx.Rect) void {
        const label = strings.t("Preview", "Visualizar");
        const bw = u.painter.measure(label, u.style.small()) + u.px(36);
        const top = area.y + u.px(if (view.find.open) 50 else 8);
        const r: gfx.Rect = .{ .x = area.right() - bw - u.px(22), .y = top, .w = bw, .h = u.px(24) };
        u.beginOverlay(r);
        defer u.endOverlay();
        const look = &editor.appearance.current;
        const id = ui_mod.child(view.id, 0x7091e);
        const clicked = u.clickable(id, r);
        const hot = u.isHot(id);
        u.painter.fillRounded(r, u.px(6), look.background.mix(look.foreground, if (hot) 0.2 else 0.12));
        u.painter.stroke(r, u.px(6), look.foreground.alpha(0.15), @max(1, u.px(1)));
        var inner = r.inset(u.px(8), 0);
        u.painter.icon(icons.phosphor.eye, u.px(12), inner.takeLeft(u.px(16)), look.foreground.alpha(0.8));
        u.painter.text(label, u.style.small(), inner, look.foreground, .{ .ellipsis = false });
        if (hot) u.cursor = .hand;
        if (clicked) self.controller.runToggle(self.path());
    }
};

test {
    @import("win32").refAllDeep(@This());
}
