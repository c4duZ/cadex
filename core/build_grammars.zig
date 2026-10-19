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

/// TRE, the regular expressions of the content search and the editor's
/// highlight queries, the same engine on the Mac and on Windows
/// (docs/adr/0013-regex-tre.md). Bytes only (no wchar, no locale), as the
/// system's TRE behaved under the core's "C" locale; no approximate
/// matching. The two headers configure stands in for come from here.
pub fn addTre(b: *std.Build, root: *std.Build.Module, target: std.Build.ResolvedTarget) ?*std.Build.Step.Compile {
    const dep = b.lazyDependency("tre", .{}) orelse return null;
    const headers = b.addWriteFiles();
    _ = headers.add("config.h",
        \\#define HAVE_SYS_TYPES_H 1
        \\#define HAVE_ISASCII 1
        \\#define HAVE_ISBLANK 1
        \\#define TRE_REGEX_T_FIELD value
        \\#define TRE_VERSION "0.9.0"
        \\#define TRE_VERSION_1 0
        \\#define TRE_VERSION_2 9
        \\#define TRE_VERSION_3 0
        \\
    );
    _ = headers.add("tre-config.h",
        \\#define HAVE_SYS_TYPES_H 1
        \\#define TRE_VERSION "0.9.0"
        \\#define TRE_VERSION_1 0
        \\#define TRE_VERSION_2 9
        \\#define TRE_VERSION_3 0
        \\
    );
    const lib = cLibrary(b, target, "tre");
    lib.root_module.addIncludePath(headers.getDirectory());
    lib.root_module.addIncludePath(dep.path("lib"));
    lib.root_module.addCSourceFiles(.{
        .root = dep.path("lib"),
        .files = &.{ "tre-ast.c", "tre-compile.c", "tre-match-backtrack.c", "tre-match-parallel.c", "tre-mem.c", "tre-parse.c", "tre-stack.c", "regcomp.c", "regexec.c", "regerror.c" },
        .flags = treFlags(b),
    });
    root.linkLibrary(lib);
    return lib;
}

/// Every global symbol of TRE 0.9.0 (nm on the built library), renamed
/// cadex_tre_*: macOS's libc carries its own TRE and exports the same names,
/// and the app's linker bound tre_compile to libSystem, where it is not
/// really there (dyld "Symbol not found: _tre_compile", 2026-10-19).
const tre_symbols = [_][]const u8{
    "tre_ast_new_catenation",
    "tre_ast_new_iter",
    "tre_ast_new_literal",
    "tre_ast_new_node",
    "tre_ast_new_union",
    "tre_compile",
    "tre_config",
    "tre_ctype",
    "tre_ctype_map",
    "tre_fill_pmatch",
    "tre_free",
    "tre_have_approx",
    "tre_have_backrefs",
    "tre_isalnum_func",
    "tre_isalpha_func",
    "tre_isascii_func",
    "tre_isblank_func",
    "tre_iscntrl_func",
    "tre_isdigit_func",
    "tre_isgraph_func",
    "tre_islower_func",
    "tre_isprint_func",
    "tre_ispunct_func",
    "tre_isspace_func",
    "tre_isupper_func",
    "tre_isxdigit_func",
    "tre_mem_alloc_impl",
    "tre_mem_destroy",
    "tre_mem_new_impl",
    "tre_parse",
    "tre_regcomp",
    "tre_regcompb",
    "tre_regerror",
    "tre_regexec",
    "tre_regexecb",
    "tre_regfree",
    "tre_regncomp",
    "tre_regncompb",
    "tre_regnexec",
    "tre_regnexecb",
    "tre_reguexec",
    "tre_stack_destroy",
    "tre_stack_new",
    "tre_stack_num_objects",
    "tre_stack_pop_int",
    "tre_stack_pop_voidptr",
    "tre_stack_push_int",
    "tre_stack_push_voidptr",
    "tre_tnfa_run_backtrack",
    "tre_tnfa_run_parallel",
    "tre_version",
};

fn treFlags(b: *std.Build) []const []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    flags.appendSlice(b.allocator, &.{ "-std=c99", "-DHAVE_CONFIG_H" }) catch @panic("OOM");
    for (tre_symbols) |name| flags.append(b.allocator, b.fmt("-D{s}=cadex_{s}", .{ name, name })) catch @panic("OOM");
    return flags.items;
}

fn cLibrary(b: *std.Build, target: std.Build.ResolvedTarget, name: []const u8) *std.Build.Step.Compile {
    const module = b.createModule(.{ .target = target, .optimize = .ReleaseSmall, .link_libc = true });
    return b.addLibrary(.{ .name = name, .linkage = .static, .root_module = module });
}
