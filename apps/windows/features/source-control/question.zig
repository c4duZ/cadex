//! The questions before acting (docs/spec/source-control.md, "Ações
//! destrutivas"): discard, commit everything when nothing is staged, and
//! publish a branch without an upstream. Drawn over the window by
//! SourceControl.frame, so a command from the palette asks even with the
//! sidebar hidden. The Mac's texts (SourceControlController.swift).

const std = @import("std");
const ui = @import("ui");
const status_mod = @import("status.zig");
const repository = @import("repository.zig");
const jobs = @import("jobs.zig");
const controller = @import("controller.zig");

const SourceControl = controller.SourceControl;
const Entry = status_mod.Entry;

pub const Kind = enum { discard, commit_all, publish };

pub const Pending = struct {
    kind: Kind,
    title: []u8,
    detail: []const u8,
    button: []const u8,
    /// discard: the tracked paths; publish: the branch.
    items: [][:0]u8 = &.{},
    /// discard: the new files, for the Recycle Bin.
    untracked: [][]u8 = &.{},

    pub fn deinit(self: *Pending, gpa: std.mem.Allocator) void {
        gpa.free(self.title);
        for (self.items) |s| gpa.free(s);
        gpa.free(self.items);
        for (self.untracked) |s| gpa.free(s);
        gpa.free(self.untracked);
    }
};

fn open(sc: *SourceControl, pending: Pending) void {
    if (sc.question) |*q| q.deinit(sc.gpa);
    sc.question = pending;
}

pub fn askDiscard(sc: *SourceControl, entries: []const Entry) void {
    const gpa = sc.gpa;
    const title = if (entries.len == 1)
        std.fmt.allocPrint(gpa, "Descartar as mudanças em {s}?", .{entries[0].path})
    else
        std.fmt.allocPrint(gpa, "Descartar as mudanças em {d} arquivos?", .{entries.len});
    const title_text = title catch return;
    var tracked: std.ArrayList([:0]u8) = .empty;
    var untracked: std.ArrayList([]u8) = .empty;
    for (entries) |e| {
        if (e.kind == .untracked) {
            untracked.append(gpa, gpa.dupe(u8, e.path) catch continue) catch {};
        } else {
            tracked.append(gpa, repository.z(gpa, e.path) catch continue) catch {};
        }
    }
    open(sc, .{
        .kind = .discard,
        .title = title_text,
        .detail = "Isso não pode ser desfeito (arquivos novos vão para a Lixeira).",
        .button = "Descartar",
        .items = tracked.toOwnedSlice(gpa) catch &.{},
        .untracked = untracked.toOwnedSlice(gpa) catch &.{},
    });
}

pub fn askCommitAll(sc: *SourceControl) void {
    open(sc, .{
        .kind = .commit_all,
        .title = sc.gpa.dupe(u8, "Nada está staged. Fazer o commit de todas as mudanças?") catch return,
        .detail = "",
        .button = "Commit de tudo",
    });
}

pub fn askPublish(sc: *SourceControl, branch: []const u8) void {
    const gpa = sc.gpa;
    const items = gpa.alloc([:0]u8, 1) catch return;
    items[0] = repository.z(gpa, branch) catch return gpa.free(items);
    open(sc, .{
        .kind = .publish,
        .title = std.fmt.allocPrint(gpa, "Publicar a branch {s}?", .{branch}) catch {
            gpa.free(items[0]);
            return gpa.free(items);
        },
        .detail = "Ela vai para o origin e passa a ser acompanhada.",
        .button = "Publicar",
        .items = items,
    });
}

pub fn draw(sc: *SourceControl, u: *ui.Ui) void {
    const q = &(sc.question orelse return);
    const choice = ui.menu.ask(u, .{ .title = q.title, .message = q.detail, .buttons = &.{ q.button, "Cancelar" } }) orelse return;
    var pending = q.*;
    sc.question = null;
    defer pending.deinit(sc.gpa);
    if (choice == 0) answer(sc, &pending);
}

fn answer(sc: *SourceControl, q: *Pending) void {
    const root = sc.root orelse return;
    switch (q.kind) {
        .discard => {
            for (q.untracked) |rel| {
                const path = repository.absolute(sc.gpa, root, rel) catch continue;
                defer sc.gpa.free(path);
                if (!sc.host.trash(sc.host.context, path)) {
                    const text = std.fmt.allocPrint(sc.gpa, "Não foi possível mandar {s} para a Lixeira", .{rel}) catch continue;
                    defer sc.gpa.free(text);
                    sc.showError(text);
                }
            }
            if (q.items.len == 0) return sc.refresh();
            // The job owns the paths now.
            jobs.Run.submit(sc, root, .{ .paths = .{ .which = .discard, .list = q.items } });
            q.items = &.{};
        },
        .commit_all => sc.commitNow(root, true),
        .publish => {
            jobs.Run.submit(sc, root, .{ .push = q.items[0] });
            sc.gpa.free(q.items);
            q.items = &.{};
        },
    }
}

test {
    @import("win32").refAllDeep(@This());
}
