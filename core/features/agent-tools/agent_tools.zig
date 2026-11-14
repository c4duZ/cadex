//! agent-tools: the `cadex` program that the agent sessions Cadex opens
//! run (docs/spec/agent-tools.md). Born with one subcommand, `statusline`
//! (docs/plans/18-accounts-and-sessions.md, phase B); plans 19 and 20 add
//! more. No interface: it reads, writes small files and prints.

pub const statusline = @import("statusline.zig");
pub const cli = @import("cli.zig");

test {
    _ = statusline;
    _ = cli;
}
