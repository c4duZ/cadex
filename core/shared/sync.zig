//! A mutex and a condition variable that need no std.Io (Zig 0.16 moved
//! std.Thread.Mutex there): pthread on the Mac, SRWLOCK on Windows. Used by
//! the terminal sessions, the workspace registry, the search and Markdown
//! indexes, the editor's query cache and the explorer's watcher.

const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("win32.zig");

const is_windows = builtin.os.tag == .windows;

pub const Mutex = struct {
    raw: if (is_windows) win32.SRWLOCK else std.c.pthread_mutex_t = if (is_windows) .{} else std.c.PTHREAD_MUTEX_INITIALIZER,

    pub fn lock(self: *Mutex) void {
        if (is_windows) win32.AcquireSRWLockExclusive(&self.raw) else _ = std.c.pthread_mutex_lock(&self.raw);
    }

    pub fn unlock(self: *Mutex) void {
        if (is_windows) win32.ReleaseSRWLockExclusive(&self.raw) else _ = std.c.pthread_mutex_unlock(&self.raw);
    }
};

pub const Condition = struct {
    raw: if (is_windows) win32.CONDITION_VARIABLE else std.c.pthread_cond_t = if (is_windows) .{} else std.c.PTHREAD_COND_INITIALIZER,

    /// Releases `mutex` while waiting; holds it again on return. Wakes up
    /// spuriously too, so callers wait in a loop on their own condition.
    pub fn wait(self: *Condition, mutex: *Mutex) void {
        if (is_windows) {
            _ = win32.SleepConditionVariableSRW(&self.raw, &mutex.raw, win32.INFINITE, 0);
        } else {
            _ = std.c.pthread_cond_wait(&self.raw, &mutex.raw);
        }
    }

    pub fn signal(self: *Condition) void {
        if (is_windows) win32.WakeConditionVariable(&self.raw) else _ = std.c.pthread_cond_signal(&self.raw);
    }
};

test "a waiter wakes on signal" {
    const Shared = struct {
        mutex: Mutex = .{},
        cond: Condition = .{},
        ready: bool = false,

        fn post(self: *@This()) void {
            self.mutex.lock();
            self.ready = true;
            self.cond.signal();
            self.mutex.unlock();
        }
    };
    var shared: Shared = .{};
    const thread = try std.Thread.spawn(.{}, Shared.post, .{&shared});
    shared.mutex.lock();
    while (!shared.ready) shared.cond.wait(&shared.mutex);
    shared.mutex.unlock();
    thread.join();
}
