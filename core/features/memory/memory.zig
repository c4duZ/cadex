//! memory: the client side of the project memory in the core
//! (docs/spec/memory.md, docs/adr/0028-project-memory.md). The engine is the
//! Rust process in server/; this is the only code that talks to its socket,
//! memory.sock (plan 22, phase C): `cadex memory-hook <event>` goes through
//! `hook`, and `cadex mcp`'s memory tools through `mcp` (phase D).

pub const hook = @import("hook_client.zig");
pub const mcp = @import("mcp_proxy.zig");

test {
    _ = @import("events.zig");
    _ = @import("context.zig");
    _ = @import("consolidate.zig");
    _ = @import("http.zig");
    _ = @import("spool.zig");
    _ = @import("launch.zig");
    _ = hook;
    _ = mcp;
}
