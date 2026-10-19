//! What a Windows session runs: the command line of the shell and, for
//! PowerShell, the shell integration that reports the current folder with
//! OSC 7 (docs/spec/terminal.md). Pure functions, so the rules are tested
//! on any system; pty_windows.zig picks the shell and starts it.

const std = @import("std");

/// Runs after the user's $PROFILE (-NoExit -EncodedCommand comes after
/// it). PowerShell 7 has LocationChangedAction, which reports each change
/// without touching the prompt, so prompt themes keep reading $? as they
/// do. Windows PowerShell may lack it: there the prompt is wrapped.
pub const integration_script =
    \\function global:__cadex_report_location {
    \\    $location = $ExecutionContext.SessionState.Path.CurrentLocation
    \\    if ($location.Provider.Name -ne 'FileSystem') { return }
    \\    $path = $location.ProviderPath.Replace('\', '/').Replace('%', '%25').Replace(' ', '%20')
    \\    [Console]::Write("$([char]27)]7;file://$env:COMPUTERNAME/$path$([char]7)")
    \\}
    \\if ($ExecutionContext.InvokeCommand.PSObject.Properties['LocationChangedAction']) {
    \\    $global:__cadex_previous_action = $ExecutionContext.InvokeCommand.LocationChangedAction
    \\    $ExecutionContext.InvokeCommand.LocationChangedAction = {
    \\        param($sender, $eventArgs)
    \\        if ($global:__cadex_previous_action) { & $global:__cadex_previous_action $sender $eventArgs }
    \\        __cadex_report_location
    \\    }
    \\} else {
    \\    $global:__cadex_prompt = $function:prompt
    \\    function global:prompt { __cadex_report_location; & $global:__cadex_prompt }
    \\}
    \\__cadex_report_location
;

/// Whether the command starts PowerShell (pwsh or Windows PowerShell), by
/// the name of its program, with or without quotes, path or ".exe".
pub fn isPowerShell(command: []const u8) bool {
    const program = programOf(command);
    const name = program[if (std.mem.lastIndexOfAny(u8, program, "\\/")) |i| i + 1 else 0..];
    const stem = if (std.ascii.endsWithIgnoreCase(name, ".exe")) name[0 .. name.len - 4] else name;
    return std.ascii.eqlIgnoreCase(stem, "pwsh") or std.ascii.eqlIgnoreCase(stem, "powershell");
}

fn programOf(command: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, command, " ");
    if (trimmed.len > 0 and trimmed[0] == '"') {
        const end = std.mem.indexOfScalarPos(u8, trimmed, 1, '"') orelse trimmed.len;
        return trimmed[1..end];
    }
    return trimmed[0 .. std.mem.indexOfScalar(u8, trimmed, ' ') orelse trimmed.len];
}

/// The command line for `command`: PowerShell started bare gets the
/// integration; a command with its own arguments, or any other shell, runs
/// as written.
pub fn commandLine(a: std.mem.Allocator, command: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, command, " ");
    const bare = std.mem.eql(u8, programOf(trimmed), trimmed) or
        (trimmed.len > 0 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"');
    if (!isPowerShell(trimmed) or !bare) return trimmed;
    return std.fmt.allocPrint(a, "{s} -NoLogo -NoExit -EncodedCommand {s}", .{ trimmed, try encoded(a, integration_script) });
}

/// -EncodedCommand takes base64 of the script in UTF-16LE.
fn encoded(a: std.mem.Allocator, script: []const u8) ![]const u8 {
    const wide = try std.unicode.wtf8ToWtf16LeAlloc(a, script);
    const bytes = std.mem.sliceAsBytes(wide);
    const out = try a.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    return std.base64.standard.Encoder.encode(out, bytes);
}

/// A folder for CreateProcessW: backslashes, which it needs (forward
/// slashes there fail).
pub fn systemPath(a: std.mem.Allocator, path: []const u8) ![]u8 {
    const out = try a.dupe(u8, path);
    std.mem.replaceScalar(u8, out, '/', '\\');
    return out;
}

const testing = std.testing;

test "PowerShell is recognized by its program name" {
    try testing.expect(isPowerShell("pwsh"));
    try testing.expect(isPowerShell("\"C:\\Program Files\\PowerShell\\7\\pwsh.exe\""));
    try testing.expect(isPowerShell("powershell.exe -NoProfile"));
    try testing.expect(!isPowerShell("cmd.exe"));
    try testing.expect(!isPowerShell("wsl.exe -d Ubuntu"));
}

test "only a bare PowerShell gets the integration" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const line = try commandLine(a, "\"C:\\Program Files\\PowerShell\\7\\pwsh.exe\"");
    try testing.expect(std.mem.startsWith(u8, line, "\"C:\\Program Files\\PowerShell\\7\\pwsh.exe\" -NoLogo -NoExit -EncodedCommand "));
    const b64 = line[std.mem.lastIndexOfScalar(u8, line, ' ').? + 1 ..];
    const raw = try a.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(b64));
    try std.base64.standard.Decoder.decode(raw, b64);
    const wide = try a.alloc(u16, raw.len / 2);
    @memcpy(std.mem.sliceAsBytes(wide), raw);
    try testing.expectEqualStrings(integration_script, try std.unicode.wtf16LeToWtf8Alloc(a, wide));
    try testing.expectEqualStrings("powershell.exe -NoProfile", try commandLine(a, "powershell.exe -NoProfile"));
    try testing.expectEqualStrings("cmd.exe", try commandLine(a, "cmd.exe"));
    try testing.expectEqualStrings("C:\\Users\\x", try systemPath(a, "C:/Users/x"));
}
