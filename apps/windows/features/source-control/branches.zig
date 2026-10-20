//! "Trocar de branch" in the palette, as the Mac's BranchSource: the local
//! branches and the remote ones not tracked yet, the current first, read
//! on the worker when the palette opens; choosing a remote one creates
//! the local branch tracking it.

const std = @import("std");
const icons = @import("icons");
const palette = @import("command-palette");
const strings = @import("strings");
const jobs = @import("jobs.zig");
const controller = @import("controller.zig");

const SourceControl = controller.SourceControl;

pub const Branches = struct {
    owner: *SourceControl = undefined,
    /// The core's listing ("local \t name" per line), or null before it came.
    text: ?[]u8 = null,
    loading: bool = false,

    pub fn deinit(self: *Branches, gpa: std.mem.Allocator) void {
        if (self.text) |t| gpa.free(t);
        self.text = null;
    }

    /// git.switch-branch: reads the branches again and opens the palette.
    pub fn open(self: *Branches) void {
        const sc = self.owner;
        const root = sc.root orelse return;
        self.deinit(sc.gpa);
        if (!self.loading) self.loading = jobs.Branches.submit(sc, root);
        sc.host.open_palette(sc.host.context, self.source());
    }

    pub fn received(self: *Branches, text: ?[]u8) void {
        self.loading = false;
        self.deinit(self.owner.gpa);
        self.text = text;
    }

    pub fn source(self: *Branches) palette.Source {
        return .{
            .context = self,
            .placeholder = strings.t("Switch to branch", "Trocar para a branch"),
            .empty_text = strings.t("No branches", "Nenhuma branch"),
            .icon = icons.phosphor.git_branch,
            .search = search,
            .choose = choose,
        };
    }

    fn search(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(palette.Item)) ?[]const u8 {
        const self: *Branches = @ptrCast(@alignCast(context));
        const text = self.text orelse return if (self.loading) strings.t("Loading…", "Carregando…") else null;
        const current = if (self.owner.status) |s| s.branch else "";
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
            const name = line[tab + 1 ..];
            const remote = std.mem.eql(u8, line[0..tab], "remote");
            if (name.len == 0) continue;
            if (query.len > 0 and std.ascii.indexOfIgnoreCase(name, query) == null) continue;
            out.append(arena, .{
                .id = line,
                .title = name,
                .detail = if (std.mem.eql(u8, name, current)) strings.t("current", "atual") else if (remote) strings.t("remote", "remota") else "",
                .icon = icons.phosphor.git_branch,
            }) catch break;
        }
        return null;
    }

    fn choose(context: *anyopaque, id: []const u8, _: palette.How) void {
        const self: *Branches = @ptrCast(@alignCast(context));
        const tab = std.mem.indexOfScalar(u8, id, '\t') orelse return;
        self.owner.switchBranch(id[tab + 1 ..], std.mem.eql(u8, id[0..tab], "remote"));
    }
};

test {
    @import("win32").refAllDeep(@This());
}
