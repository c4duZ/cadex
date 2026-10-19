//! The pseudo-terminal on Windows: ConPTY (CreatePseudoConsole), with the
//! shell in a Job Object so closing ends whatever it started. The
//! interface is `pty.zig`; `pty_posix.zig` is the Mac.
//!
//! ConPTY keeps its output pipe open after the shell exits, so a waiter
//! thread closes the console when the process ends: that is what makes the
//! reader see the end, as EOF does on the Mac.

const std = @import("std");
const w = @import("../../shared/win32.zig");
const pty = @import("pty.zig");
const shell_env = @import("shell_env.zig");
const shell_windows = @import("shell_windows.zig");

const Size = pty.Size;
const unicode = std.unicode;

/// No process directory on Windows: the current folder comes from OSC 7.
pub const DirectoryBuffer = [0]u8;

const State = struct {
    gpa: std.mem.Allocator,
    console: w.HPCON,
    console_closed: std.atomic.Value(bool) = .init(false),
    /// Our ends: we write the shell's input and read its output.
    input: w.HANDLE,
    output: w.HANDLE,
    process: w.HANDLE,
    job: w.HANDLE,
    waiter: std.Thread = undefined,

    fn closeConsole(self: *State) void {
        if (self.console_closed.swap(true, .acq_rel)) return;
        w.ClosePseudoConsole(self.console);
    }

    fn waitForExit(self: *State) void {
        _ = w.WaitForSingleObject(self.process, w.INFINITE);
        self.closeConsole();
    }
};

pub const Child = struct {
    state: *State,

    /// The configured shell, else PowerShell 7 (pwsh) when installed, else
    /// Windows PowerShell, else cmd, in `cwd`. PowerShell gets the shell
    /// integration (shell_windows.zig).
    pub fn start(gpa: std.mem.Allocator, options: pty.StartOptions) !Child {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();

        var to_shell_read: w.HANDLE = undefined;
        var to_shell_write: w.HANDLE = undefined;
        var from_shell_read: w.HANDLE = undefined;
        var from_shell_write: w.HANDLE = undefined;
        if (w.CreatePipe(&to_shell_read, &to_shell_write, null, 0) == 0) return error.ForkFailed;
        errdefer _ = w.CloseHandle(to_shell_write);
        defer _ = w.CloseHandle(to_shell_read);
        if (w.CreatePipe(&from_shell_read, &from_shell_write, null, 0) == 0) return error.ForkFailed;
        errdefer _ = w.CloseHandle(from_shell_read);
        // ConPTY duplicates its ends: ours close once it has them.
        defer _ = w.CloseHandle(from_shell_write);

        var console: w.HPCON = undefined;
        if (w.CreatePseudoConsole(coord(options.size), to_shell_read, from_shell_write, 0, &console) != 0) return error.ForkFailed;
        errdefer w.ClosePseudoConsole(console);

        const job = w.CreateJobObjectW(null, null) orelse return error.ForkFailed;
        errdefer _ = w.CloseHandle(job);
        const process = try startShell(a, console, job, options);
        errdefer _ = w.CloseHandle(process);
        errdefer _ = w.TerminateJobObject(job, 1);

        const state = try gpa.create(State);
        errdefer gpa.destroy(state);
        state.* = .{ .gpa = gpa, .console = console, .input = to_shell_write, .output = from_shell_read, .process = process, .job = job };
        state.waiter = try std.Thread.spawn(.{ .stack_size = 64 * 1024 }, State.waitForExit, .{state});
        return .{ .state = state };
    }

    /// The shell's output into `buf`: the count, or null once the console
    /// closed or `stop` turned true.
    pub fn read(self: Child, buf: []u8, stop: *const std.atomic.Value(bool)) ?usize {
        if (stop.load(.acquire)) return null;
        var n: w.DWORD = 0;
        const len: w.DWORD = @intCast(@min(buf.len, std.math.maxInt(w.DWORD)));
        if (w.ReadFile(self.state.output, buf.ptr, len, &n, null) == 0 or n == 0) return null;
        return n;
    }

    pub fn write(self: Child, bytes: []const u8) error{WriteFailed}!void {
        var rest = bytes;
        while (rest.len > 0) {
            var n: w.DWORD = 0;
            const len: w.DWORD = @intCast(@min(rest.len, 1 << 20));
            if (w.WriteFile(self.state.input, rest.ptr, len, &n, null) == 0) return error.WriteFailed;
            rest = rest[n..];
        }
    }

    pub fn resize(self: Child, size: Size) error{ResizeFailed}!void {
        if (self.state.console_closed.load(.acquire)) return;
        if (w.ResizePseudoConsole(self.state.console, coord(size)) != 0) return error.ResizeFailed;
    }

    /// Whether the shell is running something: more than one live process
    /// in its job (the shell itself is one).
    pub fn hasForegroundProcess(self: Child) bool {
        var info: w.JOBOBJECT_BASIC_ACCOUNTING_INFORMATION = undefined;
        if (w.QueryInformationJobObject(self.state.job, w.JobObjectBasicAccountingInformation, &info, @sizeOf(@TypeOf(info)), null) == 0) return false;
        return info.ActiveProcesses > 1;
    }

    /// Windows does not tell another process's folder; OSC 7 from the
    /// shell does (docs/plans/9-windows-core.md, phase E).
    pub fn currentDirectory(self: Child, buf: *DirectoryBuffer) ?[]const u8 {
        _ = self;
        _ = buf;
        return null;
    }

    /// After read() gave null on its own: the shell's exit code.
    pub fn waitExitCode(self: Child) i32 {
        _ = w.WaitForSingleObject(self.state.process, w.INFINITE);
        var code: w.DWORD = 0;
        if (w.GetExitCodeProcess(self.state.process, &code) == 0) return -1;
        return @bitCast(code);
    }

    /// Closing the console ends the reader's blocking read (and asks the
    /// shell to quit).
    pub fn unblockReader(self: Child) void {
        self.state.closeConsole();
    }

    /// After the reader stopped: ends the shell and whatever it started,
    /// unless it was reaped already, and frees everything.
    pub fn finish(self: Child, reaped: bool) void {
        const s = self.state;
        if (!reaped) _ = w.TerminateJobObject(s.job, 1);
        s.waiter.join();
        s.closeConsole();
        _ = w.CloseHandle(s.input);
        _ = w.CloseHandle(s.output);
        _ = w.CloseHandle(s.process);
        _ = w.CloseHandle(s.job);
        s.gpa.destroy(s);
    }

    /// A session that failed to open: end the shell at once.
    pub fn kill(self: Child) void {
        self.finish(false);
    }
};

fn coord(size: Size) w.COORD {
    return .{ .X = @intCast(@min(size.cols, std.math.maxInt(i16))), .Y = @intCast(@min(size.rows, std.math.maxInt(i16))) };
}

fn startShell(a: std.mem.Allocator, console: w.HPCON, job: w.HANDLE, options: pty.StartOptions) !w.HANDLE {
    const command_line = try unicode.wtf8ToWtf16LeAllocZ(a, try shell_windows.commandLine(a, try shellProgram(a, options.shell)));
    const env = try sessionEnvironment(a);
    var attribute_size: usize = 0;
    _ = w.InitializeProcThreadAttributeList(null, 1, 0, &attribute_size);
    const attributes: *anyopaque = (try a.alignedAlloc(u8, .of(usize), attribute_size)).ptr;
    if (w.InitializeProcThreadAttributeList(attributes, 1, 0, &attribute_size) == 0) return error.ForkFailed;
    defer w.DeleteProcThreadAttributeList(attributes);
    if (w.UpdateProcThreadAttribute(attributes, 0, w.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, console, @sizeOf(w.HPCON), null, null) == 0)
        return error.ForkFailed;

    var startup: w.STARTUPINFOEXW = .{ .StartupInfo = .{ .cb = @sizeOf(w.STARTUPINFOEXW) }, .lpAttributeList = attributes };
    var info: w.PROCESS_INFORMATION = undefined;
    const flags = w.EXTENDED_STARTUPINFO_PRESENT | w.CREATE_UNICODE_ENVIRONMENT | w.CREATE_SUSPENDED;
    const cwd = if (options.cwd) |dir| try unicode.wtf8ToWtf16LeAllocZ(a, try shell_windows.systemPath(a, dir)) else null;
    var started = w.CreateProcessW(null, command_line.ptr, null, null, 0, flags, @constCast(env.ptr), if (cwd) |d| d.ptr else null, &startup.StartupInfo, &info) != 0;
    // A missing cwd is not fatal: the shell starts in the app's folder.
    if (!started and cwd != null)
        started = w.CreateProcessW(null, command_line.ptr, null, null, 0, flags, @constCast(env.ptr), null, &startup.StartupInfo, &info) != 0;
    if (!started) return error.ForkFailed;
    _ = w.AssignProcessToJobObject(job, info.hProcess);
    _ = w.ResumeThread(info.hThread);
    _ = w.CloseHandle(info.hThread);
    return info.hProcess;
}

/// The shell to start, quoted when it is a found path.
fn shellProgram(a: std.mem.Allocator, configured: ?[]const u8) ![]const u8 {
    if (configured) |s| if (s.len > 0) return s;
    if (try findOnPath(a, std.unicode.wtf8ToWtf16LeStringLiteral("pwsh.exe"))) |path| return std.fmt.allocPrint(a, "\"{s}\"", .{path});
    if (try findOnPath(a, std.unicode.wtf8ToWtf16LeStringLiteral("powershell.exe"))) |path| return std.fmt.allocPrint(a, "\"{s}\"", .{path});
    return "cmd.exe";
}

fn findOnPath(a: std.mem.Allocator, name: [*:0]const u16) !?[]const u8 {
    var buf: [1024]u16 = undefined;
    const n = w.SearchPathW(null, name, null, buf.len, &buf, null);
    if (n == 0 or n >= buf.len) return null;
    return try unicode.wtf16LeToWtf8Alloc(a, buf[0..n]);
}

/// The app's environment minus the variables the terminal owns, plus its
/// own (shell_env.zig), as a UTF-16 block.
fn sessionEnvironment(a: std.mem.Allocator) ![:0]const u16 {
    var block: std.ArrayList(u16) = .empty;
    const current = w.GetEnvironmentStringsW() orelse return error.ForkFailed;
    defer _ = w.FreeEnvironmentStringsW(current);
    var at: usize = 0;
    while (current[at] != 0) {
        const entry = std.mem.sliceTo(current[at..], 0);
        at += entry.len + 1;
        if (shell_env.isOwned(try unicode.wtf16LeToWtf8Alloc(a, entry))) continue;
        try block.appendSlice(a, entry);
        try block.append(a, 0);
    }
    for (shell_env.added_vars) |entry| {
        try block.appendSlice(a, try unicode.wtf8ToWtf16LeAlloc(a, entry));
        try block.append(a, 0);
    }
    return block.toOwnedSliceSentinel(a, 0);
}

/// %USERPROFILE%, for links written as ~/path.
pub fn homeDirectory(buf: []u8) ?[]const u8 {
    return w.environmentVariable("USERPROFILE", buf);
}
