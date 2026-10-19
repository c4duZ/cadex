//! Running a program on Windows: CreateProcessW with pipes, inside a Job
//! Object so a timeout kills what it started too (git's ssh). The
//! interface is `process.zig`; `process_posix.zig` is the same on the Mac.

const std = @import("std");
const w = @import("win32.zig");
const clock = @import("clock.zig");
const process = @import("process.zig");

const Options = process.Options;
const Result = process.Result;
const unicode = std.unicode;

/// What a killed program exits with: 128 + SIGKILL, as on the Mac.
const killed_code = 137;

pub fn run(gpa: std.mem.Allocator, argv: []const []const u8, options: Options) !Result {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    const command_line = try unicode.wtf8ToWtf16LeAllocZ(a, try commandLine(a, argv));
    const env = try environment(a, options.env);
    const cwd = if (options.cwd) |dir| try unicode.wtf8ToWtf16LeAllocZ(a, dir) else null;

    var stdin_pipe = try Pipe.init(.child_reads);
    defer stdin_pipe.close();
    var stdout_pipe = try Pipe.init(.child_writes);
    defer stdout_pipe.close();
    var stderr_pipe = try Pipe.init(.child_writes);
    defer stderr_pipe.close();

    // Only these three handles reach the child: other threads spawning at
    // the same time must not leak their pipes into it, or EOF never comes
    // (the Mac gets the same from POSIX_SPAWN_CLOEXEC_DEFAULT).
    var inherited = [_]w.HANDLE{ stdin_pipe.child, stdout_pipe.child, stderr_pipe.child };
    var attributes = try HandleList.init(a, &inherited);
    defer attributes.deinit();

    var startup: w.STARTUPINFOEXW = .{
        .StartupInfo = .{
            .cb = @sizeOf(w.STARTUPINFOEXW),
            .dwFlags = w.STARTF_USESTDHANDLES,
            .hStdInput = stdin_pipe.child,
            .hStdOutput = stdout_pipe.child,
            .hStdError = stderr_pipe.child,
        },
        .lpAttributeList = attributes.list,
    };
    const job = w.CreateJobObjectW(null, null) orelse return error.SpawnFailed;
    defer _ = w.CloseHandle(job);
    var info: w.PROCESS_INFORMATION = undefined;
    const flags = w.CREATE_UNICODE_ENVIRONMENT | w.CREATE_NO_WINDOW | w.EXTENDED_STARTUPINFO_PRESENT | w.CREATE_SUSPENDED;
    if (w.CreateProcessW(null, command_line.ptr, null, null, 1, flags, @constCast(env.ptr), if (cwd) |d| d.ptr else null, &startup.StartupInfo, &info) == 0) {
        return .{ .code = -1, .stdout = try gpa.alloc(u8, 0), .stderr = try gpa.dupe(u8, "program not found"), .timed_out = false, .truncated = false };
    }
    defer _ = w.CloseHandle(info.hProcess);
    // In the job before it runs a single instruction, so nothing it starts
    // escapes the timeout.
    _ = w.AssignProcessToJobObject(job, info.hProcess);
    _ = w.ResumeThread(info.hThread);
    _ = w.CloseHandle(info.hThread);

    // Our copies of the child's ends: closed so EOF arrives when it exits.
    stdin_pipe.closeChild();
    stdout_pipe.closeChild();
    stderr_pipe.closeChild();
    if (options.stdin.len > 0) {
        var written: w.DWORD = 0;
        _ = w.WriteFile(stdin_pipe.parent, options.stdin.ptr, @intCast(options.stdin.len), &written, null);
    }
    stdin_pipe.closeParent();

    return collect(gpa, stdout_pipe.parent, stderr_pipe.parent, info.hProcess, job, options);
}

const Pipe = struct {
    parent: w.HANDLE,
    child: w.HANDLE,
    parent_open: bool = true,
    child_open: bool = true,

    fn init(direction: enum { child_reads, child_writes }) !Pipe {
        const security: w.SECURITY_ATTRIBUTES = .{ .bInheritHandle = 1 };
        var read: w.HANDLE = undefined;
        var write: w.HANDLE = undefined;
        if (w.CreatePipe(&read, &write, &security, 0) == 0) return error.SpawnFailed;
        const pipe: Pipe = switch (direction) {
            .child_reads => .{ .parent = write, .child = read },
            .child_writes => .{ .parent = read, .child = write },
        };
        _ = w.SetHandleInformation(pipe.parent, w.HANDLE_FLAG_INHERIT, 0);
        return pipe;
    }

    fn closeChild(self: *Pipe) void {
        if (self.child_open) _ = w.CloseHandle(self.child);
        self.child_open = false;
    }

    fn closeParent(self: *Pipe) void {
        if (self.parent_open) _ = w.CloseHandle(self.parent);
        self.parent_open = false;
    }

    fn close(self: *Pipe) void {
        self.closeChild();
        self.closeParent();
    }
};

/// PROC_THREAD_ATTRIBUTE_HANDLE_LIST, in memory from `a`.
const HandleList = struct {
    list: *anyopaque,

    fn init(a: std.mem.Allocator, handles: []w.HANDLE) !HandleList {
        var size: usize = 0;
        _ = w.InitializeProcThreadAttributeList(null, 1, 0, &size);
        const memory = try a.alignedAlloc(u8, .of(usize), size);
        const list: *anyopaque = memory.ptr;
        if (w.InitializeProcThreadAttributeList(list, 1, 0, &size) == 0) return error.SpawnFailed;
        errdefer w.DeleteProcThreadAttributeList(list);
        if (w.UpdateProcThreadAttribute(list, 0, w.PROC_THREAD_ATTRIBUTE_HANDLE_LIST, @ptrCast(handles.ptr), handles.len * @sizeOf(w.HANDLE), null, null) == 0)
            return error.SpawnFailed;
        return .{ .list = list };
    }

    fn deinit(self: *HandleList) void {
        w.DeleteProcThreadAttributeList(self.list);
    }
};

/// One pipe drained on its own thread: anonymous pipes cannot be waited
/// on with a timeout, so the deadline is kept by the caller instead.
const Drain = struct {
    gpa: std.mem.Allocator,
    handle: w.HANDLE,
    max: usize,
    bytes: std.ArrayList(u8) = .empty,
    truncated: bool = false,
    failed: bool = false,
    done: std.atomic.Value(bool) = .init(false),

    fn loop(self: *Drain) void {
        defer self.done.store(true, .release);
        var buf: [64 * 1024]u8 = undefined;
        while (true) {
            var n: w.DWORD = 0;
            if (w.ReadFile(self.handle, &buf, buf.len, &n, null) == 0 or n == 0) return;
            const keep = @min(self.max -| self.bytes.items.len, n);
            if (keep < n) self.truncated = true;
            self.bytes.appendSlice(self.gpa, buf[0..keep]) catch {
                self.failed = true;
                return;
            };
        }
    }
};

/// Reads both pipes until EOF or the deadline; kills the job then.
fn collect(gpa: std.mem.Allocator, out: w.HANDLE, err: w.HANDLE, child: w.HANDLE, job: w.HANDLE, options: Options) !Result {
    var drains = [_]Drain{
        .{ .gpa = gpa, .handle = out, .max = options.max_output },
        .{ .gpa = gpa, .handle = err, .max = options.max_output },
    };
    defer for (&drains) |*d| d.bytes.deinit(gpa);
    var threads: [2]std.Thread = undefined;
    for (&drains, &threads) |*d, *t| t.* = try std.Thread.spawn(.{ .stack_size = 128 * 1024 }, Drain.loop, .{d});

    const deadline = clock.monotonicMs() + options.timeout_ms;
    var timed_out = false;
    while (!(drains[0].done.load(.acquire) and drains[1].done.load(.acquire))) {
        if (clock.monotonicMs() >= deadline) {
            timed_out = true;
            // Ends every process in the job, which closes their pipe ends:
            // the drains see EOF and return.
            _ = w.TerminateJobObject(job, killed_code);
            break;
        }
        clock.sleepMs(10);
    }
    for (threads) |t| t.join();
    if (drains[0].failed or drains[1].failed) return error.OutOfMemory;

    _ = w.WaitForSingleObject(child, if (timed_out) 5_000 else w.INFINITE);
    var code: w.DWORD = 0;
    _ = w.GetExitCodeProcess(child, &code);
    return .{
        .code = if (code == w.STILL_ACTIVE) -1 else @bitCast(code),
        .stdout = try drains[0].bytes.toOwnedSlice(gpa),
        .stderr = try drains[1].bytes.toOwnedSlice(gpa),
        .timed_out = timed_out,
        .truncated = drains[0].truncated or drains[1].truncated,
    };
}

/// The argv as one command line, quoted the way the C runtime (and so git
/// and most programs) splits it back: quotes around arguments with spaces
/// or tabs, backslashes doubled only before a quote.
pub fn commandLine(a: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (argv, 0..) |arg, i| {
        if (i > 0) try out.append(a, ' ');
        const plain = arg.len > 0 and std.mem.indexOfAny(u8, arg, " \t\n\x0b\"") == null;
        if (plain) {
            try out.appendSlice(a, arg);
            continue;
        }
        try out.append(a, '"');
        var backslashes: usize = 0;
        for (arg) |ch| {
            if (ch == '\\') {
                backslashes += 1;
                continue;
            }
            const repeat = if (ch == '"') backslashes * 2 + 1 else backslashes;
            try out.appendNTimes(a, '\\', repeat);
            backslashes = 0;
            try out.append(a, ch);
        }
        // Before the closing quote, every backslash is doubled.
        try out.appendNTimes(a, '\\', backslashes * 2);
        try out.append(a, '"');
    }
    return out.items;
}

/// The app's environment plus `extra`, as a UTF-16 block ("A=1\0B=2\0\0").
/// An entry named again in `extra` is replaced; names ignore case, as
/// Windows does.
fn environment(a: std.mem.Allocator, extra: []const []const u8) ![:0]const u16 {
    var block: std.ArrayList(u16) = .empty;
    const current = w.GetEnvironmentStringsW() orelse return error.SpawnFailed;
    defer _ = w.FreeEnvironmentStringsW(current);
    var at: usize = 0;
    while (current[at] != 0) {
        const entry = std.mem.sliceTo(current[at..], 0);
        at += entry.len + 1;
        const text = try unicode.wtf16LeToWtf8Alloc(a, entry);
        if (!isReplaced(text, extra)) {
            try block.appendSlice(a, entry);
            try block.append(a, 0);
        }
    }
    for (extra) |e| {
        try block.appendSlice(a, try unicode.wtf8ToWtf16LeAlloc(a, e));
        try block.append(a, 0);
    }
    return block.toOwnedSliceSentinel(a, 0);
}

fn isReplaced(entry: []const u8, extra: []const []const u8) bool {
    // "=C:=C:\x" entries (the cmd.exe drive folders) start with '='.
    const eq = std.mem.indexOfScalarPos(u8, entry, 1, '=') orelse return false;
    const name = entry[0..eq];
    for (extra) |e| {
        if (e.len > name.len and e[name.len] == '=' and std.ascii.eqlIgnoreCase(e[0..name.len], name)) return true;
    }
    return false;
}

const testing = std.testing;

test "command lines quote the way the C runtime splits them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const line = try commandLine(arena.allocator(), &.{ "git", "commit", "-m", "olá mundo", "", "a\"b", "C:\\dir with space\\" });
    try testing.expectEqualStrings("git commit -m \"olá mundo\" \"\" \"a\\\"b\" \"C:\\dir with space\\\\\"", line);
}

test "runs without a shell, in a folder, with extra environment" {
    var r = try process.run(testing.allocator, &.{ "cmd.exe", "/d", "/c", "cd& echo %CADEX_TEST%& (echo oops)1>&2& exit 3" }, .{
        .cwd = "C:\\Windows",
        .env = &.{"CADEX_TEST=a b"},
    });
    defer r.deinit(testing.allocator);
    try testing.expectEqual(@as(i32, 3), r.code);
    try testing.expectEqualStrings("C:\\Windows\r\na b\r\n", r.stdout);
    try testing.expect(std.mem.startsWith(u8, r.stderr, "oops"));
}

test "stdin, output limit, and a time limit that kills" {
    var sorted = try process.run(testing.allocator, &.{"sort.exe"}, .{ .stdin = "0123456789\r\n", .max_output = 4 });
    defer sorted.deinit(testing.allocator);
    try testing.expectEqualStrings("0123", sorted.stdout);
    try testing.expect(sorted.truncated);
    var slow = try process.run(testing.allocator, &.{ "ping.exe", "-n", "6", "127.0.0.1" }, .{ .timeout_ms = 200 });
    defer slow.deinit(testing.allocator);
    try testing.expect(slow.timed_out);
    try testing.expect(!slow.ok());
    var missing = try process.run(testing.allocator, &.{"cadex-no-such-program"}, .{});
    defer missing.deinit(testing.allocator);
    try testing.expectEqual(@as(i32, -1), missing.code);
}
