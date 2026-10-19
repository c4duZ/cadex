const std = @import("std");
const grammars = @import("build_grammars.zig");

/// libghostty-vt features Cadex does not use, turned off to keep them out of
/// the app. kitty_graphics also drops the wuffs image decoder; snapshot is the
/// screen serialization we do not need because sessions restore without their
/// old content (docs/spec/terminal.md, "Fechar e restaurar").
const vt_features = "-kitty_graphics,-glyph_protocol,-snapshot";

pub fn build(b: *std.Build) void {
    // Not the host: the app ships to other Macs. Baseline CPU (no features
    // of this machine's chip) and macOS 13 as the oldest supported version.
    const target = b.standardTargetOptions(.{ .default_target = .{
        .os_tag = .macos,
        .os_version_min = .{ .semver = .{ .major = 13, .minor = 0, .patch = 0 } },
    } });
    const optimize = b.standardOptimizeOption(.{});

    const root = b.createModule(.{
        .root_source_file = b.path("cadex.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    linkSystem(b, root, target);

    // Only the terminal feature may import this (ADR 0003).
    const ghostty = b.lazyDependency("ghostty", .{
        .target = target,
        .optimize = optimize,
        .@"vt-features" = vt_features,
    }) orelse return;
    root.addImport("ghostty-vt", ghostty.module("ghostty-vt"));

    // tree-sitter and the grammars, for the editor (features/editor).
    const grammar_libs = grammars.add(b, root, target) orelse return;
    // md4c, for the rendered Markdown (features/markdown).
    const md4c = grammars.addMd4c(b, root, target) orelse return;
    // TRE, for the regular expressions (shared/regex.zig).
    const tre = grammars.addTre(b, root, target) orelse return;
    const c_libs = std.mem.concat(b.allocator, *std.Build.Step.Compile, &.{ grammar_libs, &.{ md4c, tre } }) catch @panic("OOM");

    const core_lib = b.addLibrary(.{
        .name = "cadex-core",
        .linkage = .static,
        .root_module = root,
    });

    // A Zig static library does not absorb the static libraries its modules
    // link, and ghostty-vt links simdutf and highway that way. The app should
    // link one file, so merge them into libcadex.a.
    installMergedLibrary(b, ghostty, core_lib, c_libs, target, optimize);
    b.installDirectory(.{
        .source_dir = b.path("include"),
        .install_dir = .header,
        .install_subdir = "",
    });

    const tests = b.addTest(.{ .root_module = root });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the core tests").dependOn(&run_tests.step);
    // The tests as an executable, for a system this Mac cannot run: the
    // Windows VM runs zig-out/bin/cadex-core-tests.exe (plan 9, phase A).
    b.step("test-bin", "Build the core tests without running them").dependOn(&b.addInstallArtifact(tests, .{ .dest_sub_path = "cadex-core-tests.exe" }).step);
}

/// What each system adds to the core. The default target stays the Mac; the
/// Windows app builds with -Dtarget=<arch>-windows.win11_zn-gnu (plan 9).
fn linkSystem(b: *std.Build, root: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .macos => {
            // FSEvents, for the explorer's file watching (features/explorer/watch.zig).
            // Zig does not look in the macOS SDK on its own when the target is not
            // the bare host ("unable to find framework 'CoreServices'", 2026-10-19);
            // usr/lib resolves the framework's own dependencies (libobjc). Setting
            // the SDK as sysroot instead doubled the path in a warning.
            const sdk = std.mem.trimEnd(u8, b.run(&.{ "xcrun", "--show-sdk-path" }), "\n");
            root.addFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "System/Library/Frameworks" }) });
            root.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "usr/lib" }) });
            root.linkFramework("CoreServices", .{});
        },
        // ConPTY, Job Objects and ReadDirectoryChangesW are all kernel32,
        // which libc (mingw) already links.
        else => {},
    }
}

fn installMergedLibrary(
    b: *std.Build,
    ghostty: *std.Build.Dependency,
    core_lib: *std.Build.Step.Compile,
    grammar_libs: []const *std.Build.Step.Compile,
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

    // Zig's own llvm-ar, not macOS libtool: libtool silently drops the Zig
    // object ("member not 8-byte aligned"), and with it every cadex_
    // function (found 2026-10-19). llvm-ar also works for the Windows app.
    // q: append, c: create, L: add the members of the input archives,
    // s: write the symbol index.
    const merge = b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "qcLs" });
    const merged = merge.addOutputFileArg("libcadex.a");
    merge.addArtifactArg(core_lib);
    merge.addArtifactArg(simdutf.artifact("simdutf"));
    merge.addArtifactArg(highway.artifact("highway"));
    for (grammar_libs) |lib| merge.addArtifactArg(lib);
    b.getInstallStep().dependOn(&b.addInstallLibFile(merged, "libcadex.a").step);
}
