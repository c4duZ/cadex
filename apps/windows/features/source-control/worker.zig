//! A background thread that runs git through the core, one job at a time
//! and in order: every cadex_git_* call blocks until git ends (up to 2
//! minutes for fetch, pull and push: core/features/source-control/git.zig),
//! index.lock forbids two gits at once, and "stage, then commit" must stay
//! in that order. The Mac does the same with a serial DispatchQueue per
//! repository (apps/macos/features/source-control/GitRepository.swift).
//!
//! Finished jobs wait in `done` until the window's thread drains them;
//! `notify` (the app's PostMessage) wakes it. Rules for a job: `work` runs
//! on the worker and reads only the job's own copies; `finish` runs on the
//! window's thread and frees the job. When the owner is gone (stop),
//! `finish` gets cancelled = true, possibly on the worker, and only frees.
//!
//! The git-history feature has its own copy of this file: a feature does
//! not reach into another (CLAUDE.md, root).

const std = @import("std");
const w = @import("win32");
const c = w.c;

pub const Job = struct {
    work: *const fn (job: *Job) void,
    finish: *const fn (job: *Job, cancelled: bool) void,
    next: ?*Job = null,
};

/// Called on the worker when a job is done; it must only post a message.
pub const Notify = struct {
    context: *anyopaque,
    post: *const fn (context: *anyopaque) void,
};

const Queue = struct {
    head: ?*Job = null,
    tail: ?*Job = null,

    fn push(self: *Queue, job: *Job) void {
        job.next = null;
        if (self.tail) |t| t.next = job else self.head = job;
        self.tail = job;
    }

    fn pop(self: *Queue) ?*Job {
        const job = self.head orelse return null;
        self.head = job.next;
        if (self.head == null) self.tail = null;
        return job;
    }

    /// Everything, in order, as a linked list.
    fn take(self: *Queue) ?*Job {
        const all = self.head;
        self.* = .{};
        return all;
    }
};

pub const Worker = struct {
    gpa: std.mem.Allocator,
    notify: Notify,
    lock: c.SRWLOCK = .{},
    wake: c.CONDITION_VARIABLE = .{},
    todo: Queue = .{},
    done: Queue = .{},
    stopping: bool = false,
    /// Submitted and not yet finished; the window's thread only.
    pending: usize = 0,

    /// The worker frees itself after stop(); never destroy it otherwise.
    pub fn create(gpa: std.mem.Allocator, notify: Notify) !*Worker {
        const self = try gpa.create(Worker);
        self.* = .{ .gpa = gpa, .notify = notify };
        // The core's own git threads use 128 KB (core/shared/process_windows.zig).
        const thread = std.Thread.spawn(.{ .stack_size = 512 * 1024 }, loop, .{self}) catch |err| {
            gpa.destroy(self);
            return err;
        };
        thread.detach();
        return self;
    }

    pub fn submit(self: *Worker, job: *Job) void {
        self.pending += 1;
        c.AcquireSRWLockExclusive(&self.lock);
        self.todo.push(job);
        c.ReleaseSRWLockExclusive(&self.lock);
        c.WakeConditionVariable(&self.wake);
    }

    /// On the window's thread, every frame: finishes what the worker did.
    /// True when something finished (the frame should show it).
    pub fn drain(self: *Worker) bool {
        c.AcquireSRWLockExclusive(&self.lock);
        var list = self.done.take();
        c.ReleaseSRWLockExclusive(&self.lock);
        const any = list != null;
        while (list) |job| {
            list = job.next;
            self.pending -|= 1;
            job.finish(job, false);
        }
        return any;
    }

    pub fn busy(self: *const Worker) bool {
        return self.pending > 0;
    }

    /// The owner goes: the worker ends after the job it is running (git
    /// has its time limit), cancels the rest and frees itself. Do not
    /// touch the worker after this.
    pub fn stop(self: *Worker) void {
        c.AcquireSRWLockExclusive(&self.lock);
        self.stopping = true;
        var list = self.done.take();
        c.ReleaseSRWLockExclusive(&self.lock);
        c.WakeConditionVariable(&self.wake);
        cancelAll(&list);
    }

    fn cancelAll(list: *?*Job) void {
        while (list.*) |job| {
            list.* = job.next;
            job.finish(job, true);
        }
    }

    fn loop(self: *Worker) void {
        while (true) {
            c.AcquireSRWLockExclusive(&self.lock);
            while (self.todo.head == null and !self.stopping) {
                _ = c.SleepConditionVariableSRW(&self.wake, &self.lock, c.INFINITE, 0);
            }
            if (self.stopping) {
                var todo = self.todo.take();
                var done = self.done.take();
                c.ReleaseSRWLockExclusive(&self.lock);
                cancelAll(&todo);
                cancelAll(&done);
                self.gpa.destroy(self);
                return;
            }
            const job = self.todo.pop().?;
            c.ReleaseSRWLockExclusive(&self.lock);
            job.work(job);
            c.AcquireSRWLockExclusive(&self.lock);
            const stopped = self.stopping;
            if (!stopped) self.done.push(job);
            c.ReleaseSRWLockExclusive(&self.lock);
            if (stopped) {
                job.finish(job, true);
            } else {
                self.notify.post(self.notify.context);
            }
        }
    }
};

test {
    @import("win32").refAllDeep(@This());
}
