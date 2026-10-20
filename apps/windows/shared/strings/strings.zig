//! The interface's texts in English (default) or Portuguese, written as a
//! pair where they are used (docs/adr/0015-english-default-two-languages.md),
//! the Mac's Strings module: `t("Open file", "Abrir arquivo")`. The app sets
//! `language` once at launch from settings.json; changing it asks to reopen.

const std = @import("std");

pub const Language = enum {
    en,
    pt,

    pub fn parse(name: []const u8) Language {
        return std.meta.stringToEnum(Language, name) orelse .en;
    }
};

/// Set by the app before any text is made, and not after.
pub var language: Language = .en;

/// The text in the interface's language; the other one is kept so the
/// palette finds a command by its title in either language.
pub fn t(en: []const u8, pt: []const u8) []const u8 {
    const shown, const other = if (language == .pt) .{ pt, en } else .{ en, pt };
    remember(shown, other);
    return shown;
}

/// Pairs seen by t, for counterpart. The UI thread only; a fixed table,
/// since the app's texts are a few hundred.
var pairs: [2048]struct { []const u8, []const u8 } = undefined;
var count: usize = 0;

fn remember(shown: []const u8, other: []const u8) void {
    if (std.mem.eql(u8, shown, other) or count == pairs.len) return;
    for (pairs[0..count]) |p| if (p[0].ptr == shown.ptr) return;
    pairs[count] = .{ shown, other };
    count += 1;
}

/// The other language's version of a text t made.
pub fn counterpart(text: []const u8) ?[]const u8 {
    for (pairs[0..count]) |p| if (std.mem.eql(u8, p[0], text)) return p[1];
    return null;
}

test "a text comes in the interface's language and knows its other version" {
    language = .en;
    try std.testing.expectEqualStrings("Open file", t("Open file", "Abrir arquivo"));
    try std.testing.expectEqualStrings("Abrir arquivo", counterpart("Open file").?);
    language = .pt;
    try std.testing.expectEqualStrings("Abrir arquivo", t("Open file", "Abrir arquivo"));
    language = .en;
    try std.testing.expectEqual(Language.pt, Language.parse("pt"));
    try std.testing.expectEqual(Language.en, Language.parse("fr"));
}
