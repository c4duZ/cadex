//! The git work of the Git page, as worker jobs (worker.zig): find the
//! repository, read the status, run an action, list the branches. Each
//! job carries copies of what it needs and hands its result back to the
//! SourceControl on the window's thread.

const std = @import("std");
const worker_mod = @import("worker.zig");
const repository = @import("repository.zig");
const controller = @import("controller.zig");

const Job = worker_mod.Job;
const SourceControl = controller.SourceControl;

pub const Find = struct {
    job: Job = .{ .work = work, .finish = finish },
    gpa: std.mem.Allocator,
    owner: *SourceControl,
    generation: u32,
    folder: [:0]u8,
    git: bool = false,
    root: ?[]u8 = null,

    pub fn submit(owner: *SourceControl, folder: []const u8) void {
        const gpa = owner.gpa;
        const self = gpa.create(Find) catch return;
        const f = repository.z(gpa, folder) catch return gpa.destroy(self);
        self.* = .{ .gpa = gpa, .owner = owner, .generation = owner.generation, .folder = f };
        owner.worker.submit(&self.job);
    }

    fn work(job: *Job) void {
        const self: *Find = @fieldParentPtr("job", job);
        self.git = repository.available();
        if (self.git) self.root = repository.findRoot(self.gpa, self.folder);
    }

    fn finish(job: *Job, cancelled: bool) void {
        const self: *Find = @fieldParentPtr("job", job);
        const gpa = self.gpa;
        if (!cancelled and self.generation == self.owner.generation) {
            self.owner.found(self.git, self.root);
            self.root = null;
        }
        if (self.root) |r| gpa.free(r);
        gpa.free(self.folder);
        gpa.destroy(self);
    }
};

pub const Status = struct {
    job: Job = .{ .work = work, .finish = finish },
    gpa: std.mem.Allocator,
    owner: *SourceControl,
    generation: u32,
    root: [:0]u8,
    text: ?[]u8 = null,

    pub fn submit(owner: *SourceControl, root: []const u8) bool {
        const gpa = owner.gpa;
        const self = gpa.create(Status) catch return false;
        const r = repository.z(gpa, root) catch {
            gpa.destroy(self);
            return false;
        };
        self.* = .{ .gpa = gpa, .owner = owner, .generation = owner.generation, .root = r };
        owner.worker.submit(&self.job);
        return true;
    }

    fn work(job: *Job) void {
        const self: *Status = @fieldParentPtr("job", job);
        self.text = repository.status(self.gpa, self.root);
    }

    fn finish(job: *Job, cancelled: bool) void {
        const self: *Status = @fieldParentPtr("job", job);
        const gpa = self.gpa;
        if (!cancelled) {
            const current = self.generation == self.owner.generation;
            self.owner.statusRead(if (current) self.text else null);
            if (current) self.text = null;
        }
        if (self.text) |t| gpa.free(t);
        gpa.free(self.root);
        gpa.destroy(self);
    }
};

pub const Action = union(enum) {
    paths: struct { which: repository.PathAction, list: [][:0]u8 },
    commit: struct { text: [:0]u8, all: bool },
    sync: repository.Sync,
    push: ?[:0]u8,
    switch_to: struct { name: [:0]u8, remote: bool },
    /// git init in this folder (no repository yet).
    init: [:0]u8,

    pub fn free(self: Action, gpa: std.mem.Allocator) void {
        switch (self) {
            .paths => |p| {
                for (p.list) |s| gpa.free(s);
                gpa.free(p.list);
            },
            .commit => |cm| gpa.free(cm.text),
            .sync => {},
            .push => |p| if (p) |b| gpa.free(b),
            .switch_to => |s| gpa.free(s.name),
            .init => |f| gpa.free(f),
        }
    }
};

pub const Run = struct {
    job: Job = .{ .work = work, .finish = finish },
    gpa: std.mem.Allocator,
    owner: *SourceControl,
    root: [:0]u8,
    action: Action,
    message: repository.Message = .{},

    /// Takes `action`'s strings (gpa-owned) in every case.
    pub fn submit(owner: *SourceControl, root: []const u8, action: Action) void {
        const gpa = owner.gpa;
        const self = gpa.create(Run) catch return action.free(gpa);
        const r = repository.z(gpa, root) catch {
            gpa.destroy(self);
            return action.free(gpa);
        };
        self.* = .{ .gpa = gpa, .owner = owner, .root = r, .action = action };
        owner.worker.submit(&self.job);
    }

    fn work(job: *Job) void {
        const self: *Run = @fieldParentPtr("job", job);
        self.message = switch (self.action) {
            .paths => |p| repository.onPaths(p.which, self.root, p.list),
            .commit => |cm| repository.commit(self.root, cm.text, cm.all),
            .sync => |s| repository.sync(s, self.root),
            .push => |branch| repository.push(self.root, branch),
            .switch_to => |s| repository.switchTo(self.root, s.name, s.remote),
            .init => |folder| repository.initialize(folder),
        };
    }

    fn finish(job: *Job, cancelled: bool) void {
        const self: *Run = @fieldParentPtr("job", job);
        const gpa = self.gpa;
        if (!cancelled) self.owner.actionDone(&self.message, std.meta.activeTag(self.action));
        self.action.free(gpa);
        gpa.free(self.root);
        gpa.destroy(self);
    }
};

pub const Branches = struct {
    job: Job = .{ .work = work, .finish = finish },
    gpa: std.mem.Allocator,
    owner: *SourceControl,
    root: [:0]u8,
    text: ?[]u8 = null,

    pub fn submit(owner: *SourceControl, root: []const u8) bool {
        const gpa = owner.gpa;
        const self = gpa.create(Branches) catch return false;
        const r = repository.z(gpa, root) catch {
            gpa.destroy(self);
            return false;
        };
        self.* = .{ .gpa = gpa, .owner = owner, .root = r };
        owner.worker.submit(&self.job);
        return true;
    }

    fn work(job: *Job) void {
        const self: *Branches = @fieldParentPtr("job", job);
        self.text = repository.branches(self.gpa, self.root);
    }

    fn finish(job: *Job, cancelled: bool) void {
        const self: *Branches = @fieldParentPtr("job", job);
        const gpa = self.gpa;
        if (!cancelled) {
            self.owner.branches.received(self.text);
            self.text = null;
        }
        if (self.text) |t| gpa.free(t);
        gpa.free(self.root);
        gpa.destroy(self);
    }
};

test {
    @import("win32").refAllDeep(@This());
}
