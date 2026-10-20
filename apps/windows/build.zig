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

    const root = b.createModule(.{
        .root_source_file = b.path("app/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "cadex", .module = cadex },
            .{ .name = "win32", .module = win32 },
            .{ .name = "gfx", .module = gfx },
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
}
