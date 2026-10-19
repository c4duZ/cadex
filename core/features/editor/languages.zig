//! The languages the editor highlights (docs/spec/editor.md): which file
//! names map to which tree-sitter grammar, and its highlight query. A
//! grammar's query can build on another's (TypeScript on JavaScript, C++ on
//! C), as the grammars' own packages intend.

const std = @import("std");
const ts = @import("ts.zig").c;

extern fn tree_sitter_javascript() *const ts.TSLanguage;
extern fn tree_sitter_typescript() *const ts.TSLanguage;
extern fn tree_sitter_tsx() *const ts.TSLanguage;
extern fn tree_sitter_python() *const ts.TSLanguage;
extern fn tree_sitter_rust() *const ts.TSLanguage;
extern fn tree_sitter_go() *const ts.TSLanguage;
extern fn tree_sitter_swift() *const ts.TSLanguage;
extern fn tree_sitter_zig() *const ts.TSLanguage;
extern fn tree_sitter_c() *const ts.TSLanguage;
extern fn tree_sitter_cpp() *const ts.TSLanguage;
extern fn tree_sitter_java() *const ts.TSLanguage;
extern fn tree_sitter_html() *const ts.TSLanguage;
extern fn tree_sitter_css() *const ts.TSLanguage;
extern fn tree_sitter_json() *const ts.TSLanguage;
extern fn tree_sitter_yaml() *const ts.TSLanguage;
extern fn tree_sitter_toml() *const ts.TSLanguage;
extern fn tree_sitter_bash() *const ts.TSLanguage;
extern fn tree_sitter_markdown() *const ts.TSLanguage;
extern fn tree_sitter_markdown_inline() *const ts.TSLanguage;

pub const Id = enum {
    javascript,
    jsx,
    typescript,
    tsx,
    python,
    rust,
    go,
    swift,
    zig,
    c,
    cpp,
    java,
    html,
    css,
    json,
    yaml,
    toml,
    bash,
    markdown,
    /// Only for markdown documents: the inline grammar over its paragraphs.
    markdown_inline,
};

pub const Language = struct {
    id: Id,
    /// Shown to the user and returned by the C API.
    name: [:0]const u8,
    grammar: *const fn () callconv(.c) *const ts.TSLanguage,
    highlights: []const u8,
};

const js = @embedFile("hl_javascript");
const jsx = @embedFile("hl_javascript_jsx");
const typescript_query = @embedFile("hl_typescript");
const c_query = @embedFile("hl_c");

pub const all = [_]Language{
    .{ .id = .javascript, .name = "JavaScript", .grammar = tree_sitter_javascript, .highlights = js },
    .{ .id = .jsx, .name = "JavaScript (JSX)", .grammar = tree_sitter_javascript, .highlights = js ++ jsx },
    .{ .id = .typescript, .name = "TypeScript", .grammar = tree_sitter_typescript, .highlights = js ++ typescript_query },
    .{ .id = .tsx, .name = "TypeScript (TSX)", .grammar = tree_sitter_tsx, .highlights = js ++ jsx ++ typescript_query },
    .{ .id = .python, .name = "Python", .grammar = tree_sitter_python, .highlights = @embedFile("hl_python") },
    .{ .id = .rust, .name = "Rust", .grammar = tree_sitter_rust, .highlights = @embedFile("hl_rust") },
    .{ .id = .go, .name = "Go", .grammar = tree_sitter_go, .highlights = @embedFile("hl_go") },
    .{ .id = .swift, .name = "Swift", .grammar = tree_sitter_swift, .highlights = @embedFile("hl_swift") },
    .{ .id = .zig, .name = "Zig", .grammar = tree_sitter_zig, .highlights = @embedFile("hl_zig") },
    .{ .id = .c, .name = "C", .grammar = tree_sitter_c, .highlights = c_query },
    .{ .id = .cpp, .name = "C++", .grammar = tree_sitter_cpp, .highlights = c_query ++ @embedFile("hl_cpp") },
    .{ .id = .java, .name = "Java", .grammar = tree_sitter_java, .highlights = @embedFile("hl_java") },
    .{ .id = .html, .name = "HTML", .grammar = tree_sitter_html, .highlights = @embedFile("hl_html") },
    .{ .id = .css, .name = "CSS", .grammar = tree_sitter_css, .highlights = @embedFile("hl_css") },
    .{ .id = .json, .name = "JSON", .grammar = tree_sitter_json, .highlights = @embedFile("hl_json") },
    .{ .id = .yaml, .name = "YAML", .grammar = tree_sitter_yaml, .highlights = @embedFile("hl_yaml") },
    .{ .id = .toml, .name = "TOML", .grammar = tree_sitter_toml, .highlights = @embedFile("hl_toml") },
    .{ .id = .bash, .name = "Shell", .grammar = tree_sitter_bash, .highlights = @embedFile("hl_bash") },
    .{ .id = .markdown, .name = "Markdown", .grammar = tree_sitter_markdown, .highlights = @embedFile("hl_markdown") },
    .{ .id = .markdown_inline, .name = "Markdown", .grammar = tree_sitter_markdown_inline, .highlights = @embedFile("hl_markdown_inline") },
};

pub fn get(id: Id) *const Language {
    return &all[@intFromEnum(id)];
}

const by_extension = std.StaticStringMap(Id).initComptime(.{
    .{ "js", .javascript },   .{ "mjs", .javascript }, .{ "cjs", .javascript }, .{ "jsx", .jsx },
    .{ "ts", .typescript },   .{ "mts", .typescript }, .{ "cts", .typescript }, .{ "tsx", .tsx },
    .{ "py", .python },       .{ "pyi", .python },     .{ "rs", .rust },        .{ "go", .go },
    .{ "swift", .swift },     .{ "zig", .zig },        .{ "zon", .zig },        .{ "c", .c },
    .{ "h", .c },             .{ "cpp", .cpp },        .{ "cc", .cpp },         .{ "cxx", .cpp },
    .{ "hpp", .cpp },         .{ "hh", .cpp },         .{ "hxx", .cpp },        .{ "java", .java },
    .{ "html", .html },       .{ "htm", .html },       .{ "css", .css },        .{ "json", .json },
    .{ "jsonc", .json },      .{ "yaml", .yaml },      .{ "yml", .yaml },       .{ "toml", .toml },
    .{ "sh", .bash },         .{ "bash", .bash },      .{ "zsh", .bash },       .{ "md", .markdown },
    .{ "markdown", .markdown },
});

const by_name = std.StaticStringMap(Id).initComptime(.{
    .{ ".bashrc", .bash },  .{ ".zshrc", .bash }, .{ ".profile", .bash }, .{ ".bash_profile", .bash },
    .{ ".zprofile", .bash }, .{ "Cargo.lock", .toml }, .{ "Pipfile", .toml },
});

/// The language of a file, by its name; null for plain text.
pub fn forFileName(path: []const u8) ?*const Language {
    const name = std.fs.path.basename(path);
    if (by_name.get(name)) |id| return get(id);
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return null;
    if (dot == 0) return null;
    var lower: [16]u8 = undefined;
    const ext = name[dot + 1 ..];
    if (ext.len > lower.len) return null;
    const id = by_extension.get(std.ascii.lowerString(&lower, ext)) orelse return null;
    return get(id);
}

test "languages by file name" {
    const testing = std.testing;
    try testing.expectEqual(Id.zig, forFileName("core/render.zig").?.id);
    try testing.expectEqual(Id.tsx, forFileName("App.TSX").?.id);
    try testing.expectEqual(Id.bash, forFileName("/Users/x/.zshrc").?.id);
    try testing.expect(forFileName("Makefile") == null);
    try testing.expect(forFileName(".gitignore") == null);
    for (all, 0..) |language, i| try testing.expectEqual(@as(usize, i), @intFromEnum(language.id));
}
