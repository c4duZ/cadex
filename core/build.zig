const std = @import("std");

/// libghostty-vt features Cadex does not use, turned off to keep them out of
/// the app. kitty_graphics also drops the wuffs image decoder; snapshot is the
/// screen serialization we do not need because sessions restore without their
/// old content (docs/spec/terminal.md, "Fechar e restaurar").
const vt_features = "-kitty_graphics,-glyph_protocol,-snapshot";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root = b.createModule(.{
        .root_source_file = b.path("cadex.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Only the terminal feature may import this (ADR 0003).
    const ghostty = b.lazyDependency("ghostty", .{
        .target = target,
        .optimize = optimize,
        .@"vt-features" = vt_features,
    }) orelse return;
    root.addImport("ghostty-vt", ghostty.module("ghostty-vt"));

    const core_lib = b.addLibrary(.{
        .name = "cadex-core",
        .linkage = .static,
        .root_module = root,
    });

    // A Zig static library does not absorb the static libraries its modules
    // link, and ghostty-vt links simdutf and highway that way. The app should
    // link one file, so merge them into libcadex.a.
    installMergedLibrary(b, ghostty, core_lib, target, optimize);
    b.installDirectory(.{
        .source_dir = b.path("include"),
        .install_dir = .header,
        .install_subdir = "",
    });

    const tests = b.addTest(.{ .root_module = root });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the core tests").dependOn(&run_tests.step);
}

fn installMergedLibrary(
    b: *std.Build,
    ghostty: *std.Build.Dependency,
    core_lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    // Same arguments ghostty-vt passes, so Zig reuses the same build of each.
    const simdutf = ghostty.builder.lazyDependency("simdutf", .{
        .target = target,
        .optimize = optimize,
        .no_libcxx = true,
    }) orelse return;
    const highway = ghostty.builder.lazyDependency("highway", .{
        .target = target,
        .optimize = optimize,
    }) orelse return;

    // macOS libtool. The Windows app will need lib.exe here (ADR 0001).
    const merge = b.addSystemCommand(&.{ "libtool", "-static", "-no_warning_for_no_symbols", "-o" });
    const merged = merge.addOutputFileArg("libcadex.a");
    merge.addArtifactArg(core_lib);
    merge.addArtifactArg(simdutf.artifact("simdutf"));
    merge.addArtifactArg(highway.artifact("highway"));
    b.getInstallStep().dependOn(&b.addInstallLibFile(merged, "libcadex.a").step);
}
