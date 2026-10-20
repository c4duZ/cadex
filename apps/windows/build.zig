//! The Windows app (docs/adr/0012-windows-zig-win32-d3d11.md): Zig on Win32,
//! cross-compiled from the Mac. It reaches the core only through its C API:
//! core/include/cadex.h translated to the "cadex" module, and the
//! libcadex.a that `make windows-core` builds.

const std = @import("std");

/// The system DLLs the app calls (import libraries from mingw).
const system_libs = [_][]const u8{
    "user32", "gdi32",   "dwmapi", "uxtheme", "shcore",         "imm32", "ole32", "shell32",
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
        .imports = &.{.{ .name = "gfx", .module = gfx }},
    });
    // The same font file the Mac ships: one source for the icons (ADR 0008).
    icons.addAnonymousImport("phosphor_font", .{ .root_source_file = b.path("../macos/shared/icons/Resources/Phosphor-Regular.ttf") });

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
        },
    });
    root.addObjectFile(.{ .cwd_relative = b.pathFromRoot(core_lib) });
    // simdutf and highway inside libcadex.a are C++ (built without libc++,
    // but they still need its ABI pieces).
    root.link_libcpp = true;
    for (system_libs) |lib| root.linkSystemLibrary(lib, .{});

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
        .{ "app", root }, .{ "ui", ui }, .{ "gfx", gfx }, .{ "icons", icons }, .{ "win32", win32 },
    };
    for (tested) |entry| {
        const t = b.addTest(.{ .name = entry[0], .root_module = entry[1] });
        test_step.dependOn(&b.addInstallArtifact(t, .{ .dest_sub_path = b.fmt("cadex-{s}-tests.exe", .{entry[0]}) }).step);
    }
}
