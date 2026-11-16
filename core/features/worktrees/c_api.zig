//! The worktrees feature's part of the C API (include/cadex.h). Listings
//! are lines of tab-separated fields; a refused action returns
//! CADEX_IO_FAILED with git's message.

const std = @import("std");
const status_code = @import("../../status.zig");
const workspace = @import("../workspace/workspace.zig");
const c_buffer = @import("../../shared/c_buffer.zig");
const wt = @import("worktrees.zig");

const Code = status_code.Code;
const gpa = std.heap.c_allocator;

fn span(p: ?[*:0]const u8) ?[]const u8 {
    return std.mem.span(p orelse return null);
}

/// The branch a task's name becomes ("Corrigir login" -> "corrigir-login").
pub export fn cadex_worktrees_branch_name(name: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) Code {
    c_buffer.clearOut(out, out_len);
    const n = span(name) orelse return status_code.invalid_argument;
    const branch = wt.tasks.branchName(gpa, n) catch return status_code.out_of_memory;
    defer gpa.free(branch);
    return c_buffer.handOut(branch, out, out_len);
}

/// "path \t branch \t head" per worktree, the main one first.
pub export fn cadex_worktrees_list(repo: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) Code {
    c_buffer.clearOut(out, out_len);
    const r = span(repo) orelse return status_code.invalid_argument;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const list = wt.tasks.list(arena.allocator(), workspace.registry(), r) catch |err| return status_code.fromError(err);
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    for (list) |w| {
        text.print(gpa, "{s}\t{s}\t{s}\n", .{ w.path, w.branch, w.head }) catch return status_code.out_of_memory;
    }
    return c_buffer.handOut(text.items, out, out_len);
}

/// A new branch from `base` in a new worktree at `path` (its parent folder
/// authorized). CADEX_IO_FAILED: git refused, its message in *message.
pub export fn cadex_worktrees_create(repo: ?[*:0]const u8, path: ?[*:0]const u8, branch: ?[*:0]const u8, base: ?[*:0]const u8,
                                     message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    const p = span(path) orelse return status_code.invalid_argument;
    const b = span(branch) orelse return status_code.invalid_argument;
    const from = span(base) orelse return status_code.invalid_argument;
    return finish(wt.tasks.create(gpa, workspace.registry(), r, p, b, from), message, message_len);
}

/// Copies what `.worktreeinclude` names; *copied files and folders, and in
/// *unmatched the lines that matched nothing, one per line.
pub export fn cadex_worktrees_copy_includes(repo: ?[*:0]const u8, worktree: ?[*:0]const u8, copied: ?*usize,
                                            unmatched: ?*?[*]u8, unmatched_len: ?*usize) callconv(.c) Code {
    c_buffer.clearOut(unmatched, unmatched_len);
    const r = span(repo) orelse return status_code.invalid_argument;
    const w = span(worktree) orelse return status_code.invalid_argument;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const report = wt.include.copy(arena.allocator(), workspace.registry(), r, w) catch |err| return status_code.fromError(err);
    if (copied) |c| c.* = report.copied;
    return c_buffer.handOut(report.unmatched, unmatched, unmatched_len);
}

/// What taking the worktree away would lose, one per line (changed files,
/// then "commit <oid> <subject>" for commits on no other branch); empty: safe.
pub export fn cadex_worktrees_what_would_be_lost(path: ?[*:0]const u8, branch: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) Code {
    c_buffer.clearOut(out, out_len);
    const p = span(path) orelse return status_code.invalid_argument;
    const b = span(branch) orelse "";
    const text = wt.tasks.whatWouldBeLost(gpa, workspace.registry(), p, b) catch |err| return status_code.fromError(err);
    defer gpa.free(text);
    return c_buffer.handOut(text, out, out_len);
}

/// Takes the worktree away and, with `branch` not NULL, its branch when merged.
pub export fn cadex_worktrees_remove(repo: ?[*:0]const u8, path: ?[*:0]const u8, branch: ?[*:0]const u8,
                                     message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    const p = span(path) orelse return status_code.invalid_argument;
    return finish(wt.tasks.remove(gpa, workspace.registry(), r, p, span(branch)), message, message_len);
}

/// `git worktree prune`: forgets the worktrees whose folder is gone.
pub export fn cadex_worktrees_prune(repo: ?[*:0]const u8, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    return finish(wt.tasks.prune(gpa, workspace.registry(), r), message, message_len);
}

/// `git branch -D <branch>`, merged or not.
pub export fn cadex_worktrees_delete_branch(repo: ?[*:0]const u8, branch: ?[*:0]const u8, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    const b = span(branch) orelse return status_code.invalid_argument;
    return finish(wt.tasks.deleteBranch(gpa, workspace.registry(), r, b), message, message_len);
}

fn finish(result: anyerror!?[]u8, message: ?*?[*]u8, message_len: ?*usize) Code {
    c_buffer.clearOut(message, message_len);
    const err_text = result catch |err| return status_code.fromError(err);
    const text = err_text orelse return status_code.ok;
    defer gpa.free(text);
    _ = c_buffer.handOut(text, message, message_len);
    return status_code.io_failed;
}
