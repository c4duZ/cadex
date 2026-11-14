//! Root of the `cadex` program (features/agent-tools). At the core's root
//! so it can use shared/, which a module rooted in the feature could not.

pub const main = @import("features/agent-tools/cli.zig").main;
