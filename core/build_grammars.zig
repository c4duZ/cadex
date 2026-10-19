//! Build of tree-sitter and the grammars the editor highlights
//! (docs/plans/5-viewers.md, fase A). Each grammar is a package in
//! build.zig.zon; its parser.c (and scanner.c) compile as C into one static
//! library, and its highlights.scm reaches the Zig code as an anonymous
//! import that core/features/editor/languages.zig embeds.

const std = @import("std");

const Grammar = struct {
    /// The package in build.zig.zon.
    dep: []const u8,
    /// Folder of the grammar inside the package ("" when at the top).
    dir: []const u8 = "",
    scanner: bool,
    /// Import name of its highlights.scm, or null (another entry's query
    /// serves it).
    query: ?[]const u8,
    /// Where that file is, when not `<dir>/queries/highlights.scm`.
    query_path: ?[]const u8 = null,
};

const grammars = [_]Grammar{
    .{ .dep = "ts_javascript", .scanner = true, .query = "hl_javascript" },
    .{ .dep = "ts_typescript", .dir = "typescript", .scanner = true, .query = "hl_typescript", .query_path = "queries/highlights.scm" },
    .{ .dep = "ts_typescript", .dir = "tsx", .scanner = true, .query = null },
    .{ .dep = "ts_python", .scanner = true, .query = "hl_python" },
    .{ .dep = "ts_rust", .scanner = true, .query = "hl_rust" },
    .{ .dep = "ts_go", .scanner = false, .query = "hl_go" },
    .{ .dep = "ts_swift", .scanner = true, .query = "hl_swift" },
    .{ .dep = "ts_zig", .scanner = false, .query = "hl_zig" },
    .{ .dep = "ts_c", .scanner = false, .query = "hl_c" },
    .{ .dep = "ts_cpp", .scanner = true, .query = "hl_cpp" },
    .{ .dep = "ts_java", .scanner = false, .query = "hl_java" },
    .{ .dep = "ts_html", .scanner = true, .query = "hl_html" },
    .{ .dep = "ts_css", .scanner = true, .query = "hl_css" },
    .{ .dep = "ts_json", .scanner = false, .query = "hl_json" },
    .{ .dep = "ts_yaml", .scanner = true, .query = "hl_yaml" },
    .{ .dep = "ts_toml", .scanner = true, .query = "hl_toml" },
    .{ .dep = "ts_bash", .scanner = true, .query = "hl_bash" },
    .{ .dep = "ts_markdown", .dir = "tree-sitter-markdown", .scanner = true, .query = "hl_markdown" },
    .{ .dep = "ts_markdown", .dir = "tree-sitter-markdown-inline", .scanner = true, .query = "hl_markdown_inline" },
};

/// Query files besides each grammar's highlights.scm: JSX on top of
/// JavaScript (for .jsx and .tsx).
const extra_queries = [_]struct { name: []const u8, dep: []const u8, path: []const u8 }{
    .{ .name = "hl_javascript_jsx", .dep = "ts_javascript", .path = "queries/highlights-jsx.scm" },
};

/// The tree-sitter runtime and each grammar as static libraries, linked
/// into `root` and returned for merging into libcadex.a. One library per
/// grammar: each parser.c needs its own tree_sitter/parser.h, and they
/// differ between grammar versions. Grammars are tables of data: compiled
/// small even in Debug, or a Debug build of the tests takes minutes.
pub fn add(b: *std.Build, root: *std.Build.Module, target: std.Build.ResolvedTarget) ?[]const *std.Build.Step.Compile {
    var libs: std.ArrayList(*std.Build.Step.Compile) = .empty;
    const runtime_dep = b.lazyDependency("tree_sitter", .{}) orelse return null;
    const runtime = cLibrary(b, target, "tree-sitter");
    runtime.root_module.addCSourceFile(.{ .file = runtime_dep.path("lib/src/lib.c"), .flags = &.{"-std=c11"} });
    runtime.root_module.addIncludePath(runtime_dep.path("lib/include"));
    runtime.root_module.addIncludePath(runtime_dep.path("lib/src"));
    runtime.root_module.addCMacro("_DARWIN_C_SOURCE", "");
    root.addIncludePath(runtime_dep.path("lib/include"));
    libs.append(b.allocator, runtime) catch @panic("OOM");

    for (grammars) |g| {
        const dep = b.lazyDependency(g.dep, .{}) orelse return null;
        const src = if (g.dir.len == 0) "src" else b.fmt("{s}/src", .{g.dir});
        const lib = cLibrary(b, target, b.fmt("{s}-{s}", .{ g.dep, g.dir }));
        lib.root_module.addIncludePath(dep.path(src));
        lib.root_module.addCSourceFile(.{ .file = dep.path(b.fmt("{s}/parser.c", .{src})), .flags = &.{"-std=c11"} });
        if (g.scanner) lib.root_module.addCSourceFile(.{ .file = dep.path(b.fmt("{s}/scanner.c", .{src})), .flags = &.{"-std=c11"} });
        if (g.query) |name| {
            const path = g.query_path orelse if (g.dir.len == 0) "queries/highlights.scm" else b.fmt("{s}/queries/highlights.scm", .{g.dir});
            root.addAnonymousImport(name, .{ .root_source_file = dep.path(path) });
        }
        libs.append(b.allocator, lib) catch @panic("OOM");
    }
    for (extra_queries) |q| {
        const dep = b.lazyDependency(q.dep, .{}) orelse return null;
        root.addAnonymousImport(q.name, .{ .root_source_file = dep.path(q.path) });
    }
    for (libs.items) |lib| root.linkLibrary(lib);
    return libs.items;
}

/// md4c, the Markdown parser of the rendered view (docs/adr/0010-markdown-rendering.md).
/// Only the parser: the HTML comes from core/features/markdown.
pub fn addMd4c(b: *std.Build, root: *std.Build.Module, target: std.Build.ResolvedTarget) ?*std.Build.Step.Compile {
    const dep = b.lazyDependency("md4c", .{}) orelse return null;
    const lib = cLibrary(b, target, "md4c");
    lib.root_module.addCSourceFile(.{ .file = dep.path("src/md4c.c"), .flags = &.{"-std=c99"} });
    lib.root_module.addIncludePath(dep.path("src"));
    root.addIncludePath(dep.path("src"));
    root.linkLibrary(lib);
    return lib;
}

fn cLibrary(b: *std.Build, target: std.Build.ResolvedTarget, name: []const u8) *std.Build.Step.Compile {
    const module = b.createModule(.{ .target = target, .optimize = .ReleaseSmall, .link_libc = true });
    return b.addLibrary(.{ .name = name, .linkage = .static, .root_module = module });
}
