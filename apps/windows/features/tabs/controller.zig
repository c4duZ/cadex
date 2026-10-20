//! The tabs of a window (docs/spec/tabs.md): open in the current folder,
//! switch, split, move the focus, close (asking when a program runs or a
//! document is unsaved), and open documents beside the terminal by the
//! four rules of the spec.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const terminal = @import("terminal");
const pane_tree = @import("pane_tree.zig");
const tab_mod = @import("tab.zig");
const TabList = @import("tab_list.zig").TabList;
const Document = @import("document.zig").Document;

const Tab = tab_mod.Tab;
const Pane = tab_mod.Pane;

pub const OpenFiles = enum { beside, tab };

/// What the tabs need from the app.
pub const Host = struct {
    context: *anyopaque,
    /// A new terminal pane in `cwd` (null: the user's folder), or null when
    /// the shell could not start.
    make_terminal: *const fn (context: *anyopaque, cwd: ?[]const u8) ?*terminal.View,
    /// The user's folder, for "~" titles.
    home: *const fn (context: *anyopaque) ?[]const u8,
    /// general.confirmClose.
    confirm_close: *const fn (context: *anyopaque) bool,
    /// The last tab closed: the window closes.
    on_empty: *const fn (context: *anyopaque) void,
    /// Something to save changed (the spaces).
    on_change: *const fn (context: *anyopaque) void,
};

/// What is being closed while a question is open.
pub const Closing = union(enum) {
    pane: struct { tab: u32, pane: u32 },
    tab: u32,
    /// The window or the app: every tab of `tabs` at once.
    all,
};

pub const Question = struct {
    closing: Closing,
    title: []const u8,
    message: []const u8,
    /// Unsaved documents: Salvar / Descartar / Cancelar; programs: Fechar / Cancelar.
    unsaved: bool,
};

pub const Tabs = struct {
    gpa: std.mem.Allocator,
    host: Host,
    list: TabList,
    tabs: std.AutoHashMapUnmanaged(u32, *Tab) = .empty,
    next_tab: u32 = 1,
    next_pane: u32 = 1,
    /// The question in progress, drawn by the app (bar.zig asks it).
    question: ?Question = null,
    /// Set when closing everything was confirmed: the app may go.
    closed_all: bool = false,

    pub fn init(gpa: std.mem.Allocator, host: Host) Tabs {
        return .{ .gpa = gpa, .host = host, .list = .{ .gpa = gpa } };
    }

    pub fn deinit(self: *Tabs) void {
        var it = self.tabs.valueIterator();
        while (it.next()) |t| t.*.deinit();
        self.tabs.deinit(self.gpa);
        self.list.deinit();
    }

    pub fn active(self: *Tabs) ?*Tab {
        return self.tabs.get(self.list.active orelse return null);
    }

    pub fn focusedTerminal(self: *Tabs) ?*terminal.View {
        const t = self.active() orelse return null;
        return switch (t.focused()) {
            .terminal => |v| v,
            .document => null,
        };
    }

    pub fn focusedDocument(self: *Tabs) ?Document {
        const t = self.active() orelse return null;
        return switch (t.focused()) {
            .document => |d| d,
            .terminal => null,
        };
    }

    /// The folder of the focused pane: the terminal's, or the document's.
    pub fn currentFolder(self: *Tabs, arena: std.mem.Allocator) ?[]const u8 {
        const t = self.active() orelse return null;
        switch (t.focused()) {
            .terminal => |v| {
                const dir = v.session.workingDirectory() orelse return null;
                defer dir.free();
                return arena.dupe(u8, dir.bytes) catch null;
            },
            .document => |d| return d.folder(),
        }
    }

    fn newPaneId(self: *Tabs) u32 {
        defer self.next_pane += 1;
        return self.next_pane;
    }

    /// A terminal tab in `cwd` (null: the focused pane's folder), right of the active one.
    pub fn newTab(self: *Tabs, cwd: ?[]const u8) void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const folder = cwd orelse self.currentFolder(arena.allocator());
        const view = self.host.make_terminal(self.host.context, folder) orelse return;
        self.addTab(.{ .terminal = view });
    }

    pub fn addTab(self: *Tabs, pane: Pane) void {
        const id = self.next_tab;
        self.next_tab += 1;
        const t = Tab.init(self.gpa, id, self.newPaneId(), pane) catch {
            pane.destroy(self.gpa);
            return;
        };
        self.tabs.put(self.gpa, id, t) catch {
            t.deinit();
            return;
        };
        self.list.insert(id);
        self.host.on_change(self.host.context);
    }

    pub fn select(self: *Tabs, id: u32) void {
        self.list.select(id);
        self.host.on_change(self.host.context);
    }

    /// Ctrl+Shift+D (right) and Ctrl+Shift+Alt+D (down): a terminal beside
    /// the focused pane, in its folder.
    pub fn split(self: *Tabs, axis: pane_tree.Axis) void {
        const t = self.active() orelse return self.newTab(null);
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const view = self.host.make_terminal(self.host.context, self.currentFolder(arena.allocator())) orelse return;
        t.split(axis, self.newPaneId(), .{ .terminal = view }) catch {
            const pane: Pane = .{ .terminal = view };
            pane.destroy(self.gpa);
        };
        self.host.on_change(self.host.context);
    }

    pub fn focusPane(self: *Tabs, pane: u32) void {
        const t = self.active() orelse return;
        if (t.panes.get(pane) == null) return;
        t.focus = pane;
        self.host.on_change(self.host.context);
    }

    pub fn cycleFocus(self: *Tabs, step: i32) void {
        const t = self.active() orelse return;
        if (t.tree.cycle(t.focus, step)) |p| self.focusPane(p);
    }

    pub fn moveFocus(self: *Tabs, direction: pane_tree.Direction, area: gfx.Rect) void {
        const t = self.active() orelse return;
        if (t.tree.neighbor(t.focus, direction, area)) |p| self.focusPane(p);
    }

    /// Ctrl+Shift+W: the focused pane, asking first when it runs a program
    /// or holds unsaved changes.
    pub fn closeFocused(self: *Tabs) void {
        const t = self.active() orelse return;
        self.requestClose(.{ .pane = .{ .tab = t.id, .pane = t.focus } });
    }

    pub fn requestClose(self: *Tabs, closing: Closing) void {
        if (self.question != null) return;
        var unsaved: usize = 0;
        var running: usize = 0;
        self.count(closing, &unsaved, &running);
        if (unsaved > 0) {
            self.question = .{ .closing = closing, .title = if (unsaved == 1) "Salvar as mudanças?" else "Salvar os arquivos alterados?", .message = "Há mudanças que ainda não foram salvas.", .unsaved = true };
        } else if (running > 0 and self.host.confirm_close(self.host.context)) {
            self.question = .{ .closing = closing, .title = "Fechar com um programa rodando?", .message = "O programa no terminal será encerrado.", .unsaved = false };
        } else {
            self.finishClose(closing);
        }
    }

    fn count(self: *Tabs, closing: Closing, unsaved: *usize, running: *usize) void {
        const tally = struct {
            fn pane(p: Pane, u: *usize, r: *usize) void {
                switch (p) {
                    .terminal => |v| if (v.session.hasForegroundProcess()) {
                        r.* += 1;
                    },
                    .document => |d| if (d.unsaved()) {
                        u.* += 1;
                    },
                }
            }
        };
        switch (closing) {
            .pane => |pp| if (self.tabs.get(pp.tab)) |t| if (t.panes.get(pp.pane)) |p| tally.pane(p, unsaved, running),
            .tab => |id| if (self.tabs.get(id)) |t| for (t.panes.values()) |p| tally.pane(p, unsaved, running),
            .all => {
                var it = self.tabs.valueIterator();
                while (it.next()) |t| for (t.*.panes.values()) |p| tally.pane(p, unsaved, running);
            },
        }
    }

    /// The user answered the question: 0 save (or close), 1 discard, last cancel.
    pub fn answer(self: *Tabs, choice: usize) void {
        const q = self.question orelse return;
        self.question = null;
        if (q.unsaved) {
            if (choice == 2) return;
            if (choice == 0 and !self.saveAll(q.closing)) return;
        } else if (choice != 0) return;
        self.finishClose(q.closing);
    }

    fn saveAll(self: *Tabs, closing: Closing) bool {
        var ok = true;
        const each = struct {
            fn save(p: Pane, all_ok: *bool) void {
                if (p == .document and p.document.unsaved() and !p.document.save()) all_ok.* = false;
            }
        };
        switch (closing) {
            .pane => |pp| if (self.tabs.get(pp.tab)) |t| if (t.panes.get(pp.pane)) |p| each.save(p, &ok),
            .tab => |id| if (self.tabs.get(id)) |t| for (t.panes.values()) |p| each.save(p, &ok),
            .all => {
                var it = self.tabs.valueIterator();
                while (it.next()) |t| for (t.*.panes.values()) |p| each.save(p, &ok);
            },
        }
        return ok;
    }

    fn finishClose(self: *Tabs, closing: Closing) void {
        switch (closing) {
            .pane => |pp| self.closePaneNow(pp.tab, pp.pane),
            .tab => |id| self.closeTabNow(id),
            .all => {
                self.closed_all = true;
                return self.host.on_empty(self.host.context);
            },
        }
        self.host.on_change(self.host.context);
    }

    pub fn closePaneNow(self: *Tabs, tab_id: u32, pane_id: u32) void {
        const t = self.tabs.get(tab_id) orelse return;
        const pane = t.panes.get(pane_id) orelse return;
        if (!t.remove(pane_id)) return self.closeTabNow(tab_id);
        pane.destroy(self.gpa);
    }

    pub fn closeTabNow(self: *Tabs, tab_id: u32) void {
        const t = self.tabs.get(tab_id) orelse return;
        _ = self.tabs.remove(tab_id);
        self.list.remove(tab_id);
        t.deinit();
        if (self.list.order.items.len == 0) self.host.on_empty(self.host.context);
    }

    /// Where a terminal pane lives (its shell ended, its title changed).
    pub fn find(self: *Tabs, session: *terminal.Session) ?struct { tab: *Tab, pane: u32, view: *terminal.View } {
        var it = self.tabs.valueIterator();
        while (it.next()) |t| {
            for (t.*.panes.keys(), t.*.panes.values()) |id, p| switch (p) {
                .terminal => |v| if (v.session == session) return .{ .tab = t.*, .pane = id, .view = v },
                .document => {},
            };
        }
        return null;
    }

    /// Opens a document by the four rules of "Ao lado", or in its own tab.
    /// `doc` is destroyed when a pane already shows the same identity.
    pub fn open(self: *Tabs, doc: Document, where: OpenFiles, keeping: ?Document) void {
        // (1) A pane already shows it: go there.
        var it = self.tabs.valueIterator();
        while (it.next()) |t| for (t.*.panes.keys(), t.*.panes.values()) |id, p| {
            if (p == .document and std.mem.eql(u8, p.document.identity(), doc.identity())) {
                doc.destroy();
                self.list.select(t.*.id);
                t.*.focus = id;
                return self.host.on_change(self.host.context);
            }
        };
        const t = self.active() orelse return self.addTab(.{ .document = doc });
        if (where == .tab) return self.addTab(.{ .document = doc });
        // (2) The tab's document pane, if saved and not the one asking, takes it.
        if (t.documentPane()) |pane_id| {
            const old = t.panes.get(pane_id).?.document;
            const asking = if (keeping) |k| k.ptr == old.ptr else false;
            if (!old.unsaved() and !asking) {
                t.panes.put(self.gpa, pane_id, .{ .document = doc }) catch return doc.destroy();
                old.destroy();
                t.focus = pane_id;
                return self.host.on_change(self.host.context);
            }
        }
        // (3) Split the focused pane; (4) no room: a new tab.
        if (t.tree.count() >= 6) return self.addTab(.{ .document = doc });
        t.split(.horizontal, self.newPaneId(), .{ .document = doc }) catch return self.addTab(.{ .document = doc });
        self.host.on_change(self.host.context);
    }

    /// Every document of every tab (the app passes disk changes to them).
    pub fn documents(self: *Tabs, out: *std.ArrayList(Document)) void {
        var it = self.tabs.valueIterator();
        while (it.next()) |t| for (t.*.panes.values()) |p| if (p == .document) out.append(self.gpa, p.document) catch {};
    }

    /// The title of a tab: the name given, else the focused pane's folder or document title.
    pub fn title(self: *Tabs, t: *Tab, arena: std.mem.Allocator) []const u8 {
        if (t.name) |n| return n;
        switch (t.focused()) {
            .document => |d| return d.title(),
            .terminal => |v| {
                if (v.session.title()) |owned| {
                    defer owned.free();
                    if (owned.bytes.len > 0) return arena.dupe(u8, owned.bytes) catch "";
                }
                const dir = v.session.workingDirectory();
                defer if (dir) |d| d.free();
                const name = @import("tab_list.zig").folderTitle(if (dir) |d| d.bytes else null, self.host.home(self.host.context));
                return arena.dupe(u8, name) catch "~";
            },
        }
    }
};

test {
    @import("win32").refAllDeep(@This());
}
