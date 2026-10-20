//! The language of the few texts the core writes for people (a git
//! message, the name of a pasted copy), English or Portuguese as the app's
//! interface (docs/adr/0015-english-default-two-languages.md). The app sets
//! it once at launch with cadex_set_language, before any worker starts, so
//! threads only read it.

const std = @import("std");

pub const Language = enum { en, pt };

pub var current: Language = .en;

/// The text in the interface's language: `t("Git failed", "git falhou")`.
pub fn t(en: []const u8, pt: []const u8) []const u8 {
    return if (current == .pt) pt else en;
}

/// "pt" for Portuguese; anything else, English.
export fn cadex_set_language(code: [*:0]const u8) void {
    current = if (std.mem.eql(u8, std.mem.span(code), "pt")) .pt else .en;
}

test "the core speaks the app's language" {
    cadex_set_language("pt");
    try std.testing.expectEqualStrings("git falhou", t("git failed", "git falhou"));
    cadex_set_language("en");
    try std.testing.expectEqualStrings("git failed", t("git failed", "git falhou"));
}
