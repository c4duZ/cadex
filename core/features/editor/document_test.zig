//! Highlighting, folds and incremental edits on a sample of each language
//! of the MVP (docs/spec/editor.md).

const std = @import("std");
const testing = std.testing;
const Document = @import("document.zig").Document;
const Kind = @import("highlight.zig").Kind;

/// The kind painted at the first occurrence of `needle` (after `after`).
fn kindAt(doc: *Document, spans: []const @import("document.zig").Span, needle: []const u8) Kind {
    const at = std.mem.indexOf(u8, doc.text.items, needle) orelse return .none;
    for (spans) |s| {
        if (s.start <= at and at < s.end) return s.kind;
    }
    return .none;
}

const Expect = struct { needle: []const u8, kind: Kind };

fn check(file: []const u8, source: []const u8, expected: []const Expect) !void {
    const doc = try Document.open(testing.allocator, file, source, .utf8);
    defer doc.close();
    try testing.expect(doc.language != null);
    const spans = try doc.highlights(testing.allocator, 0, @intCast(source.len));
    defer testing.allocator.free(spans);
    for (expected) |e| {
        const got = kindAt(doc, spans, e.needle);
        if (got != e.kind) {
            std.debug.print("{s}: \"{s}\" is {s}, expected {s}\n", .{ file, e.needle, @tagName(got), @tagName(e.kind) });
            return error.WrongKind;
        }
    }
}

test "zig" {
    try check("a.zig",
        \\const std = @import("std");
        \\// a comment
        \\pub fn main() void {
        \\    const x: u32 = 42;
        \\}
    , &.{ .{ .needle = "const", .kind = .keyword }, .{ .needle = "\"std\"", .kind = .string }, .{ .needle = "// a", .kind = .comment }, .{ .needle = "main", .kind = .function }, .{ .needle = "42", .kind = .number }, .{ .needle = "u32", .kind = .type } });
}

test "javascript and typescript" {
    const js =
        \\// hi
        \\function greet(name) { return "hi " + name; }
        \\const n = 3;
    ;
    const want = [_]Expect{ .{ .needle = "function", .kind = .keyword }, .{ .needle = "greet", .kind = .function }, .{ .needle = "\"hi ", .kind = .string }, .{ .needle = "// hi", .kind = .comment }, .{ .needle = "3", .kind = .number } };
    try check("a.js", js, &want);
    try check("a.ts", js, &want);
    try check("a.tsx", js, &want);
    try check("a.ts", "let x: number = 1;\ninterface P { a: string }", &.{ .{ .needle = "number", .kind = .type }, .{ .needle = "interface", .kind = .keyword } });
}

test "python, rust, go, swift" {
    try check("a.py", "# c\ndef f(x):\n    return 'v'\n", &.{ .{ .needle = "def", .kind = .keyword }, .{ .needle = "f(", .kind = .function }, .{ .needle = "'v'", .kind = .string }, .{ .needle = "# c", .kind = .comment } });
    try check("a.rs", "// c\nfn main() { let s = \"x\"; }\n", &.{ .{ .needle = "fn", .kind = .keyword }, .{ .needle = "main", .kind = .function }, .{ .needle = "\"x\"", .kind = .string }, .{ .needle = "// c", .kind = .comment } });
    try check("a.go", "package main\n// c\nfunc main() { s := \"x\" }\n", &.{ .{ .needle = "func", .kind = .keyword }, .{ .needle = "main()", .kind = .function }, .{ .needle = "\"x\"", .kind = .string }, .{ .needle = "// c", .kind = .comment } });
    try check("a.swift", "// c\nfunc greet() -> String { return \"x\" }\n", &.{ .{ .needle = "func", .kind = .keyword }, .{ .needle = "greet", .kind = .function }, .{ .needle = "\"x\"", .kind = .string }, .{ .needle = "// c", .kind = .comment } });
}

test "c, c++, java" {
    try check("a.c", "/* c */\nint main(void) { return \"x\"[0]; }\n", &.{ .{ .needle = "return", .kind = .keyword }, .{ .needle = "main", .kind = .function }, .{ .needle = "\"x\"", .kind = .string }, .{ .needle = "/* c", .kind = .comment }, .{ .needle = "int", .kind = .type } });
    try check("a.cpp", "// c\nclass A { public: int f(); };\n", &.{ .{ .needle = "class", .kind = .keyword }, .{ .needle = "// c", .kind = .comment } });
    try check("A.java", "// c\nclass A { void f() { String s = \"x\"; } }\n", &.{ .{ .needle = "class", .kind = .keyword }, .{ .needle = "f()", .kind = .function }, .{ .needle = "\"x\"", .kind = .string }, .{ .needle = "// c", .kind = .comment } });
}

test "html, css, json, yaml, toml, shell" {
    try check("a.html", "<div class=\"x\">hi</div><!-- c -->", &.{ .{ .needle = "div", .kind = .tag }, .{ .needle = "class", .kind = .attribute }, .{ .needle = "<!--", .kind = .comment } });
    try check("a.css", "/* c */\n.a { color: red; }\n", &.{ .{ .needle = "/* c", .kind = .comment }, .{ .needle = "color", .kind = .property } });
    try check("a.json", "{\"a\": \"b\", \"n\": 1, \"t\": true}", &.{ .{ .needle = "\"b\"", .kind = .string }, .{ .needle = "1", .kind = .number }, .{ .needle = "true", .kind = .constant } });
    try check("a.yaml", "# c\nkey: value\nn: 3\n", &.{ .{ .needle = "# c", .kind = .comment }, .{ .needle = "key", .kind = .property }, .{ .needle = "3", .kind = .number } });
    try check("a.toml", "# c\n[pkg]\nname = \"x\"\n", &.{ .{ .needle = "# c", .kind = .comment }, .{ .needle = "\"x\"", .kind = .string } });
    try check("a.sh", "# c\nif true; then echo \"x\"; fi\n", &.{ .{ .needle = "# c", .kind = .comment }, .{ .needle = "if", .kind = .keyword }, .{ .needle = "\"x\"", .kind = .string } });
}

test "markdown: headings from the block grammar, links and code from the inline one" {
    try check("a.md", "# Title\n\nSome `code` and [a link](b.md).\n", &.{ .{ .needle = "Title", .kind = .heading }, .{ .needle = "code`", .kind = .string }, .{ .needle = "b.md", .kind = .link } });
}

test "an edit reparses incrementally and reports the changed range" {
    const source = "const a = 1;\nconst b = 2;\n";
    const doc = try Document.open(testing.allocator, "a.zig", source, .utf8);
    defer doc.close();
    // `1` becomes `"one"`: a number becomes a string.
    const changed = try doc.edit(10, 11, "\"one\"");
    try testing.expectEqualStrings("const a = \"one\";\nconst b = 2;\n", doc.text.items);
    try testing.expect(changed.start <= 10 and changed.end >= 15);
    try testing.expect(changed.end < doc.text.items.len);
    const spans = try doc.highlights(testing.allocator, 0, @intCast(doc.text.items.len));
    defer testing.allocator.free(spans);
    try testing.expectEqual(Kind.string, kindAt(doc, spans, "\"one\""));
}

test "utf-16 offsets are code units" {
    const text = std.unicode.utf8ToUtf16LeStringLiteral("// é\nconst x = 1;\n");
    const bytes = std.mem.sliceAsBytes(text);
    const doc = try Document.open(testing.allocator, "a.zig", bytes, .utf16);
    defer doc.close();
    const spans = try doc.highlights(testing.allocator, 0, @intCast(text.len));
    defer testing.allocator.free(spans);
    // "// é" is 4 code units, then the newline; `const` starts at unit 5.
    try testing.expectEqual(Kind.comment, spans[0].kind);
    try testing.expectEqual(@as(u32, 0), spans[0].start);
    try testing.expectEqual(@as(u32, 4), spans[0].end);
    try testing.expectEqual(@as(u32, 5), spans[1].start);
    try testing.expectEqual(Kind.keyword, spans[1].kind);
    const changed = try doc.edit(15, 16, std.mem.sliceAsBytes(std.unicode.utf8ToUtf16LeStringLiteral("2")));
    try testing.expect(changed.start <= 15);
}

test "folds: functions and blocks of several lines, outermost per line" {
    const source =
        \\fn a() void {
        \\    if (true) {
        \\        return;
        \\    }
        \\}
        \\const x = 1;
    ;
    const doc = try Document.open(testing.allocator, "a.zig", source, .utf8);
    defer doc.close();
    const regions = try doc.foldRegions(testing.allocator);
    defer testing.allocator.free(regions);
    try testing.expectEqual(@as(usize, 2), regions.len);
    try testing.expectEqual(@as(u32, 0), regions[0].start_row);
    try testing.expectEqual(@as(u32, 4), regions[0].end_row);
    try testing.expectEqual(@as(u32, 1), regions[1].start_row);
    try testing.expectEqual(@as(u32, 3), regions[1].end_row);
}

test "unknown names and big files are plain text" {
    const doc = try Document.open(testing.allocator, "notes.txt", "hello", .utf8);
    defer doc.close();
    try testing.expect(doc.language == null);
    const spans = try doc.highlights(testing.allocator, 0, 5);
    try testing.expectEqual(@as(usize, 0), spans.len);
    const regions = try doc.foldRegions(testing.allocator);
    try testing.expectEqual(@as(usize, 0), regions.len);
}
