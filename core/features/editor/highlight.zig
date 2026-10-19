//! What each highlighted piece of text is. Grammars name their captures
//! freely (@keyword.repeat, @text.title, @variable.member); the app paints a
//! short, fixed list of kinds with the theme's colors.

const std = @import("std");

/// Kept in sync with CADEX_TOKEN_* in include/cadex.h.
pub const Kind = enum(u8) {
    none = 0,
    keyword = 1,
    string = 2,
    number = 3,
    comment = 4,
    function = 5,
    type = 6,
    constant = 7,
    property = 8,
    operator = 9,
    punctuation = 10,
    variable = 11,
    tag = 12,
    attribute = 13,
    escape = 14,
    heading = 15,
    link = 16,
    emphasis = 17,
};

/// The kind for a capture name. Plain @variable is left uncolored: it
/// covers most identifiers, and painting them all is noise.
pub fn kindOf(capture: []const u8) Kind {
    const exact = std.StaticStringMap(Kind).initComptime(.{
        .{ "variable", .none },              .{ "variable.builtin", .variable },
        .{ "variable.parameter", .variable }, .{ "variable.member", .property },
        .{ "string.escape", .escape },       .{ "constant.builtin", .constant },
        .{ "text.title", .heading },         .{ "text.uri", .link },
        .{ "text.reference", .link },        .{ "text.literal", .string },
        .{ "text.strong", .emphasis },       .{ "text.emphasis", .emphasis },
        .{ "boolean", .constant },           .{ "label", .constant },
        .{ "delimiter", .punctuation },      .{ "character", .string },
        .{ "character.special", .escape },   .{ "constructor", .type },
    });
    if (exact.get(capture)) |kind| return kind;
    const head = if (std.mem.indexOfScalar(u8, capture, '.')) |dot| capture[0..dot] else capture;
    const by_head = std.StaticStringMap(Kind).initComptime(.{
        .{ "keyword", .keyword },     .{ "conditional", .keyword }, .{ "repeat", .keyword },
        .{ "include", .keyword },     .{ "exception", .keyword },   .{ "import", .keyword },
        .{ "media", .keyword },       .{ "keyframes", .keyword },   .{ "supports", .keyword },
        .{ "charset", .keyword },     .{ "string", .string },       .{ "number", .number },
        .{ "float", .number },        .{ "comment", .comment },     .{ "function", .function },
        .{ "method", .function },     .{ "type", .type },           .{ "namespace", .type },
        .{ "module", .type },         .{ "constant", .constant },   .{ "property", .property },
        .{ "field", .property },      .{ "operator", .operator },   .{ "punctuation", .punctuation },
        .{ "tag", .tag },             .{ "attribute", .attribute }, .{ "escape", .escape },
        .{ "markup", .emphasis },
    });
    return by_head.get(head) orelse .none;
}

test "capture names map to kinds" {
    const testing = std.testing;
    try testing.expectEqual(Kind.keyword, kindOf("keyword.repeat"));
    try testing.expectEqual(Kind.function, kindOf("function.method"));
    try testing.expectEqual(Kind.none, kindOf("variable"));
    try testing.expectEqual(Kind.property, kindOf("variable.member"));
    try testing.expectEqual(Kind.escape, kindOf("string.escape"));
    try testing.expectEqual(Kind.heading, kindOf("text.title"));
    try testing.expectEqual(Kind.none, kindOf("spell"));
}
