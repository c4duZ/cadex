//! A file open in an editor pane (docs/spec/editor.md), the tabs' Document:
//! read through the core with the Mac's limits (the head of a huge file,
//! read-only, with a notice; a binary file is a message with "Abrir no app
//! padrão"), the code view, saving when editing is on (Markdown), and
//! following the file when it changes on disk.

const std = @import("std");
const gfx = @import("gfx");
const ui_mod = @import("ui");
const icons = @import("icons");
const tabs = @import("tabs");
const file = @import("file.zig");
const view_mod = @import("view.zig");
const view_input = @import("view_input.zig");
const banner_mod = @import("banner.zig");

const Ui = ui_mod.Ui;
const View = view_mod.View;

/// What the editor needs from the app.
pub const Host = struct {
    context: *anyopaque,
    /// Opens a file in the system's default app (a binary file's button).
    open_externally: *const fn (context: *anyopaque, path: []const u8) void,
    /// The document with the keyboard (the focused pane's), for the
    /// editor.* and markdown.* commands.
    focused_document: *const fn (context: *anyopaque) ?tabs.Document,
};

const State = union(enum) {
    text: *View,
    binary,
    failed: []const u8,
};

var next_id: usize = 1;

pub const Editor = struct {
    gpa: std.mem.Allocator,
    host: Host,
    path: []u8,
    id: ui_mod.Id,
    state: State,
    banner: banner_mod.Banner = .{},
    editable: bool,
    /// Truncated or not UTF-8: saving would spoil the file.
    read_only: bool = false,
    /// The bytes on disk as last read or written.
    disk_hash: u64 = 0,
    /// The text as last saved or loaded, and the answer for one version.
    saved_hash: u64 = 0,
    unsaved_at: struct { version: u64 = std.math.maxInt(u64), value: bool = false } = .{},
    hooks: ?view_mod.Hooks = null,

    pub fn create(gpa: std.mem.Allocator, host: Host, path: []const u8, options: view_mod.Options) !*Editor {
        const self = try gpa.create(Editor);
        errdefer gpa.destroy(self);
        const owned = try gpa.dupe(u8, path);
        errdefer gpa.free(owned);
        defer next_id += 1;
        self.* = .{ .gpa = gpa, .host = host, .path = owned, .id = ui_mod.id("editor", next_id), .state = .binary, .editable = options.editable };
        self.load();
        return self;
    }

    fn load(self: *Editor) void {
        switch (file.read(self.gpa, self.path)) {
            .binary => self.state = .binary,
            .failed => |m| self.state = .{ .failed = m },
            .text => |t| {
                defer self.gpa.free(t.bytes);
                self.disk_hash = t.disk_hash;
                self.saved_hash = file.hash(t.bytes);
                self.read_only = t.truncated or !t.valid;
                const highlight = t.bytes.len <= file.max_highlight_bytes;
                const made = View.create(self.gpa, self.id, self.title(), t.bytes, highlight, .{ .editable = self.editable and !self.read_only }) catch {
                    self.state = .{ .failed = "Memória insuficiente para abrir o arquivo" };
                    return;
                };
                self.state = .{ .text = made };
                if (t.truncated) {
                    self.banner.show("Arquivo grande: mostrando os primeiros 10 MB, só para leitura.", &.{});
                } else if (!t.valid) {
                    self.banner.show("O arquivo não é UTF-8 válido: aberto só para leitura.", &.{});
                } else if (!highlight) {
                    self.banner.show("Arquivo acima de 1 MB: sem cores nem dobras.", &.{});
                }
            },
        }
    }

    pub fn view(self: *Editor) ?*View {
        return switch (self.state) {
            .text => |v| v,
            else => null,
        };
    }

    /// What another feature adds to the view (markdown).
    pub fn setHooks(self: *Editor, hooks: view_mod.Hooks) void {
        self.hooks = hooks;
        if (self.view()) |v| v.hooks = hooks;
    }

    pub fn title(self: *const Editor) []const u8 {
        return std.fs.path.basename(self.path);
    }

    pub fn unsaved(self: *Editor) bool {
        const v = self.view() orelse return false;
        if (!v.editable) return false;
        if (self.unsaved_at.version != v.buffer.version) {
            self.unsaved_at = .{ .version = v.buffer.version, .value = file.hash(v.text()) != self.saved_hash };
        }
        return self.unsaved_at.value;
    }

    /// editor.save. False (with the reason in the banner) when it could not.
    pub fn save(self: *Editor) bool {
        const v = self.view() orelse return false;
        if (self.read_only) {
            self.banner.show("Este arquivo está aberto só para leitura.", &.{});
            return false;
        }
        if (!v.editable) return true;
        if (file.write(self.gpa, self.path, v.text())) |problem| {
            self.banner.show(problem, &.{});
            return false;
        }
        self.markSaved(file.hash(v.text()));
        self.banner.hide();
        v.buffer.history.seal();
        return true;
    }

    fn markSaved(self: *Editor, hash: u64) void {
        self.disk_hash = hash;
        if (self.view()) |v| self.saved_hash = file.hash(v.text());
        self.unsaved_at = .{};
    }

    /// The file's folder changed on disk (the app watches it): take the new
    /// text when nothing is unsaved, otherwise ask in the banner.
    pub fn reload(self: *Editor) void {
        const v = self.view() orelse {
            self.banner.hide();
            self.load();
            if (self.hooks) |h| self.setHooks(h);
            return;
        };
        switch (file.read(self.gpa, self.path)) {
            .text => |t| {
                defer self.gpa.free(t.bytes);
                if (t.disk_hash == self.disk_hash) return;
                if (self.unsaved()) {
                    self.banner.show("O arquivo mudou no disco.", &.{ .reload, .keep_mine });
                    return;
                }
                self.takeDisk(v, t);
            },
            .failed => self.banner.show("O arquivo foi apagado do disco. Salvar cria de novo.", &.{}),
            .binary => {},
        }
    }

    fn takeDisk(self: *Editor, v: *View, t: file.Text) void {
        v.replaceAll(self.title(), t.bytes, t.bytes.len <= file.max_highlight_bytes) catch return;
        self.disk_hash = t.disk_hash;
        self.saved_hash = file.hash(t.bytes);
        self.unsaved_at = .{};
        self.banner.hide();
    }

    fn bannerAction(self: *Editor, action: banner_mod.Action) void {
        const v = self.view() orelse return;
        const loaded = file.read(self.gpa, self.path);
        const t = switch (loaded) {
            .text => |t| t,
            else => return self.banner.hide(),
        };
        defer self.gpa.free(t.bytes);
        switch (action) {
            .reload => self.takeDisk(v, t),
            // The disk's version is now known: later saves overwrite it.
            .keep_mine => {
                self.disk_hash = t.disk_hash;
                self.banner.hide();
            },
        }
    }

    pub fn draw(self: *Editor, u: *Ui, area: gfx.Rect, focused: bool) void {
        var rest = area;
        if (self.banner.draw(u, self.id, &rest)) |action| self.bannerAction(action);
        switch (self.state) {
            .text => |v| v.draw(u, rest, focused),
            .binary => if (banner_mod.fullMessage(u, self.id, rest, "Arquivo binário", "Abrir no app padrão")) self.host.open_externally(self.host.context, self.path),
            .failed => |m| _ = banner_mod.fullMessage(u, self.id, rest, m, null),
        }
    }

    pub fn edit(self: *Editor, u: *Ui, action: tabs.Document.EditAction) bool {
        const v = self.view() orelse return false;
        switch (action) {
            .copy => view_input.copy(v, u),
            .cut => view_input.cut(v, u),
            .paste => view_input.paste(v, u),
            .select_all => v.buffer.selectAll(),
            .find => v.find.show(u, v),
            .undo => if (v.editable) {
                _ = v.buffer.undo() catch false;
            },
            .redo => if (v.editable) {
                _ = v.buffer.redo() catch false;
            },
        }
        v.reveal_caret = true;
        return true;
    }

    pub fn destroy(self: *Editor) void {
        if (self.hooks) |h| if (h.closed) |f| f(h.context);
        if (self.view()) |v| v.destroy();
        self.gpa.free(self.path);
        self.gpa.destroy(self);
    }

    // ---- As a tabs.Document ----

    pub fn document(self: *Editor) tabs.Document {
        return .{ .ptr = self, .vtable = &vtable };
    }

    /// The editor behind a document, when it is one.
    pub fn of(doc: tabs.Document) ?*Editor {
        if (doc.vtable != &vtable) return null;
        return @ptrCast(@alignCast(doc.ptr));
    }

    fn cast(ptr: *anyopaque) *Editor {
        return @ptrCast(@alignCast(ptr));
    }

    const vtable: tabs.Document.VTable = .{
        .title = vTitle,
        .identity = vIdentity,
        .icon = vIcon,
        .icon_color = vIconColor,
        .unsaved = vUnsaved,
        .draw = vDraw,
        .focus_id = vFocusId,
        .save = vSave,
        .folder = vFolder,
        .edit = vEdit,
        .destroy = vDestroy,
    };

    fn vTitle(ptr: *anyopaque) []const u8 {
        return cast(ptr).title();
    }
    fn vIdentity(ptr: *anyopaque) []const u8 {
        return cast(ptr).path;
    }
    fn vIcon(ptr: *anyopaque) u21 {
        return icons.forFileNamed(cast(ptr).title());
    }
    fn vIconColor(ptr: *anyopaque) ?gfx.Color {
        return icons.colorForFileNamed(cast(ptr).title());
    }
    fn vUnsaved(ptr: *anyopaque) bool {
        return cast(ptr).unsaved();
    }
    fn vDraw(ptr: *anyopaque, u: *Ui, area: gfx.Rect, focused: bool) void {
        cast(ptr).draw(u, area, focused);
    }
    fn vFocusId(ptr: *anyopaque) ui_mod.Id {
        return cast(ptr).id;
    }
    fn vSave(ptr: *anyopaque) bool {
        return cast(ptr).save();
    }
    fn vFolder(ptr: *anyopaque) ?[]const u8 {
        return std.fs.path.dirname(cast(ptr).path);
    }
    fn vEdit(ptr: *anyopaque, u: *Ui, action: tabs.Document.EditAction) bool {
        return cast(ptr).edit(u, action);
    }
    fn vDestroy(ptr: *anyopaque) void {
        cast(ptr).destroy();
    }
};

test {
    @import("win32").refAllDeep(@This());
}
