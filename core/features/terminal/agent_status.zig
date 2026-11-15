//! What an agent in a terminal says it is doing, kept by model.zig from the
//! program status protocol (OSC 7501). No libghostty here: the types only.

/// What an agent in the terminal says it is doing, by the program status
/// protocol (OSC 7501; Claude Code 2.1.325 sends state, app, kind and msg,
/// test of 2026-11-14; docs/adr/0022-terminal-daemon.md). Only the root
/// record (no id) is kept: that is the program itself. Mirrors
/// cadex_agent_status in include/cadex.h.
pub const AgentState = enum(u8) { none = 0, idle = 1, working = 2, done = 3, blocked = 4, failed = 5 };
pub const AgentKind = enum(u8) { none = 0, permission = 1, question = 2, auth = 3 };
pub const AgentStatus = struct {
    state: AgentState = .none,
    kind: AgentKind = .none,
    /// "claude-code".
    app: [32]u8 = undefined,
    app_len: usize = 0,
    /// The decoded text: "approve Bash: touch x", "Creating empty file…".
    msg: [2048]u8 = undefined,
    msg_len: usize = 0,

    pub fn appName(self: *const AgentStatus) []const u8 {
        return self.app[0..self.app_len];
    }

    pub fn message(self: *const AgentStatus) []const u8 {
        return self.msg[0..self.msg_len];
    }
};
