//! Root of the `cadex-terminald` program (features/terminal, the daemon of
//! docs/adr/0022-terminal-daemon.md). At the core's root so it can use
//! shared/. Only libc, the pty and shared/: no libghostty.

pub const main = @import("features/terminal/daemon_main.zig").main;
