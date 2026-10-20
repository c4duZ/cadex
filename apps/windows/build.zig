//! The Windows app (docs/adr/0012-windows-zig-win32-d3d11.md): Zig on Win32,
//! cross-compiled from the Mac. It reaches the core only through its C API:
//! core/include/cadex.h translated to the "cadex" module, and the
//! libcadex.a that `make windows-core` builds.

const std = @import("std");

/// The system DLLs the app calls (import libraries from mingw).
const system_libs = [_][]const u8{
    "user32", "gdi32",   "advapi32", "dwmapi", "uxtheme", "shcore",         "imm32", "ole32", "shell32",
    "d3d11",  "dxgi",    "d2d1",   "dwrite",  "d3dcompiler_47", "dcomp", "windowscodecs",
};

pub fn build(b: *std.Build) void {
    // x64 by default; the arm64 test VM builds with -Dtarget=aarch64-windows.win11_zn-gnu.
    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .os_version_min = .{ .windows = .win11_zn },
        .abi = .gnu,
    } });
    const optimize = b.standardOptimizeOption(.{});
    const arch = @tagName(target.result.cpu.arch);
    const core_lib = b.option([]const u8, "core-lib", "libcadex.a for this target") orelse
        b.fmt("../../core/zig-out/windows-{s}/lib/libcadex.a", .{arch});

    const cadex = b.addTranslateC(.{
        .root_source_file = b.path("../../core/include/cadex.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    // The Windows SDK from the headers Zig ships, with the COM vtables in
    // their exact order (docs/adr/0012-windows-zig-win32-d3d11.md).
    const sdk = b.addTranslateC(.{
        .root_source_file = b.path("shared/win32/sdk.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }).createModule();
    const win32 = b.createModule(.{
        .root_source_file = b.path("shared/win32/win32.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "sdk", .module = sdk }},
    });

    const gfx = b.createModule(.{
        .root_source_file = b.path("shared/gfx/gfx.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "win32", .module = win32 }},
    });

    const ui = b.createModule(.{
        .root_source_file = b.path("shared/ui/ui.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "win32", .module = win32 }, .{ .name = "gfx", .module = gfx } },
    });
    const icons = b.createModule(.{
        .root_source_file = b.path("shared/icons/icons.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "gfx", .module = gfx }, .{ .name = "win32", .module = win32 } },
    });
    // The same font file the Mac ships: one source for the icons (ADR 0008).
    icons.addAnonymousImport("phosphor_font", .{ .root_source_file = b.path("../macos/shared/icons/Resources/Phosphor-Regular.ttf") });

    // The shared modules build test exes of their own, which need the
    // system DLLs too.
    for ([_]*std.Build.Module{ win32, gfx, ui, icons }) |m| linkCore(m, b.pathFromRoot(core_lib));
    const shared = Shared{ .cadex = cadex, .win32 = win32, .gfx = gfx, .ui = ui, .icons = icons, .core_lib = b.pathFromRoot(core_lib) };
    const command_palette = feature(b, target, optimize, shared, "command-palette", "command_palette.zig", &.{});
    const themes = feature(b, target, optimize, shared, "themes", "themes.zig", &.{});
    // The same catalog the Mac ships: one source for the themes.
    themes.addAnonymousImport("theme_catalog", .{ .root_source_file = b.path("../macos/features/themes/Resources/catalog.json") });
    const terminal = feature(b, target, optimize, shared, "terminal", "terminal.zig", &.{});
    const tabs = feature(b, target, optimize, shared, "tabs", "tabs.zig", &.{ .{ "terminal", terminal }, .{ "command-palette", command_palette } });
    const editor = feature(b, target, optimize, shared, "editor", "editor.zig", &.{ .{ "tabs", tabs }, .{ "command-palette", command_palette } });
    const markdown = feature(b, target, optimize, shared, "markdown", "markdown.zig", &.{ .{ "editor", editor }, .{ "tabs", tabs }, .{ "command-palette", command_palette } });
    const status_bar = feature(b, target, optimize, shared, "status-bar", "status_bar.zig", &.{});
    const settings = feature(b, target, optimize, shared, "settings", "settings.zig", &.{});
    const shortcuts = feature(b, target, optimize, shared, "shortcuts", "shortcuts.zig", &.{.{ "command-palette", command_palette }});

    const root = b.createModule(.{
        .root_source_file = b.path("app/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "cadex", .module = cadex },
            .{ .name = "win32", .module = win32 },
            .{ .name = "gfx", .module = gfx },
            .{ .name = "ui", .module = ui },
            .{ .name = "icons", .module = icons },
            .{ .name = "command-palette", .module = command_palette },
            .{ .name = "shortcuts", .module = shortcuts },
            .{ .name = "themes", .module = themes },
            .{ .name = "settings", .module = settings },
            .{ .name = "terminal", .module = terminal },
            .{ .name = "tabs", .module = tabs },
            .{ .name = "editor", .module = editor },
            .{ .name = "markdown", .module = markdown },
            .{ .name = "status-bar", .module = status_bar },
        },
    });
    linkCore(root, b.pathFromRoot(core_lib));

    const exe = b.addExecutable(.{
        .name = "Cadex",
        .root_module = root,
        .win32_manifest = b.path("app/Cadex.manifest"),
    });
    exe.subsystem = .windows;
    b.installArtifact(exe);

    // Each module's tests as a Windows exe, run in the VM. A test build only
    // covers its root module, so every module gets its own; building them
    // also type-checks every declaration (Zig only analyzes what is used).
    const test_step = b.step("test-bin", "Build the app tests without running them");
    const tested = [_]struct { []const u8, *std.Build.Module }{
        .{ "app", root },                       .{ "ui", ui }, .{ "gfx", gfx }, .{ "icons", icons }, .{ "win32", win32 },
        .{ "command-palette", command_palette }, .{ "shortcuts", shortcuts }, .{ "themes", themes }, .{ "settings", settings }, .{ "terminal", terminal }, .{ "tabs", tabs }, .{ "status-bar", status_bar }, .{ "editor", editor }, .{ "markdown", markdown },
    };
    for (tested) |entry| {
        const t = b.addTest(.{ .name = entry[0], .root_module = entry[1] });
        test_step.dependOn(&b.addInstallArtifact(t, .{ .dest_sub_path = b.fmt("cadex-{s}-tests.exe", .{entry[0]}) }).step);
    }
}

/// The modules every feature may import: the core's C API and the shared layers.
const Shared = struct {
    cadex: *std.Build.Module,
    win32: *std.Build.Module,
    gfx: *std.Build.Module,
    ui: *std.Build.Module,
    icons: *std.Build.Module,
    core_lib: []const u8,
};

/// libcadex.a and the system DLLs, on every module that ends up in an exe
/// (the app and each feature's test exe); the same archive twice in one
/// link is harmless.
fn linkCore(module: *std.Build.Module, core_lib: []const u8) void {
    module.addObjectFile(.{ .cwd_relative = core_lib });
    // simdutf and highway inside libcadex.a are C++ (built without libc++,
    // but they still need its ABI pieces).
    module.link_libcpp = true;
    for (system_libs) |lib| module.linkSystemLibrary(lib, .{});
}

/// A feature as its own module (features/<dir>/<root>): it sees the shared
/// layers and only the entry points of the features in `uses`, so "a
/// feature never reaches into another" is enforced by the compiler, as
/// SwiftPM does on the Mac.
fn feature(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    shared: Shared,
    comptime dir: []const u8,
    comptime root: []const u8,
    uses: []const struct { []const u8, *std.Build.Module },
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("features/" ++ dir ++ "/" ++ root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "cadex", .module = shared.cadex },
            .{ .name = "win32", .module = shared.win32 },
            .{ .name = "gfx", .module = shared.gfx },
            .{ .name = "ui", .module = shared.ui },
            .{ .name = "icons", .module = shared.icons },
        },
    });
    for (uses) |entry| module.addImport(entry[0], entry[1]);
    linkCore(module, shared.core_lib);
    return module;
}
