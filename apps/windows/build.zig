//! The Windows app (docs/adr/0012-windows-zig-win32-d3d11.md): Zig on Win32,
//! cross-compiled from the Mac. It reaches the core only through its C API:
//! core/include/cadex.h translated to the "cadex" module, and the
//! libcadex.a that `make windows-core` builds.

const std = @import("std");

/// The system DLLs the app calls (import libraries from mingw).
const system_libs = [_][]const u8{
    "user32", "gdi32",   "advapi32", "dwmapi", "uxtheme", "shcore",         "imm32", "ole32", "shell32",
    "d3d11",  "dxgi",    "d2d1",   "dwrite",  "d3dcompiler_47", "dcomp", "windowscodecs",
    // SHCreateMemStream and SHCreateStreamOnFileEx for the pages the app serves (shared/webview).
    "shlwapi",
    // ChooseColorW, the accent color's dialog (plan 15).
    "comdlg32",
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

    // The interface's texts in English or Portuguese (ADR 0015).
    const strings = b.createModule(.{
        .root_source_file = b.path("shared/strings/strings.zig"),
        .target = target,
        .optimize = optimize,
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
    icons.addAnonymousImport("phosphor_fill_font", .{ .root_source_file = b.path("../macos/shared/icons/Resources/Phosphor-Fill.ttf") });

    // The shared modules build test exes of their own, which need the
    // system DLLs too.
    // WebView2 child windows for the web panes (docs/adr/0014-webview2-on-windows.md).
    const webview = b.createModule(.{
        .root_source_file = b.path("shared/webview/webview.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "win32", .module = win32 }, .{ .name = "gfx", .module = gfx }, .{ .name = "ui", .module = ui }, .{ .name = "strings", .module = strings } },
    });
    // Microsoft's loader goes next to Cadex.exe (and the test exes), where
    // shared/webview/loader.zig looks for it.
    const loader_arch = if (target.result.cpu.arch == .aarch64) "arm64" else "x64";
    b.getInstallStep().dependOn(&b.addInstallBinFile(b.path(b.fmt("shared/webview/sdk/{s}/WebView2Loader.dll", .{loader_arch})), "WebView2Loader.dll").step);

    for ([_]*std.Build.Module{ win32, gfx, ui, icons, webview }) |m| linkCore(m, b.pathFromRoot(core_lib));
    const shared = Shared{ .cadex = cadex, .win32 = win32, .gfx = gfx, .ui = ui, .icons = icons, .strings = strings, .core_lib = b.pathFromRoot(core_lib) };
    const command_palette = feature(b, target, optimize, shared, "command-palette", "command_palette.zig", &.{});
    const themes = feature(b, target, optimize, shared, "themes", "themes.zig", &.{});
    // The same catalog the Mac ships: one source for the themes.
    themes.addAnonymousImport("theme_catalog", .{ .root_source_file = b.path("../macos/features/themes/Resources/catalog.json") });
    const terminal = feature(b, target, optimize, shared, "terminal", "terminal.zig", &.{});
    const tabs = feature(b, target, optimize, shared, "tabs", "tabs.zig", &.{ .{ "terminal", terminal }, .{ "command-palette", command_palette } });
    const editor = feature(b, target, optimize, shared, "editor", "editor.zig", &.{ .{ "tabs", tabs }, .{ "command-palette", command_palette } });
    const markdown = feature(b, target, optimize, shared, "markdown", "markdown.zig", &.{ .{ "editor", editor }, .{ "tabs", tabs }, .{ "command-palette", command_palette } });
    const status_bar = feature(b, target, optimize, shared, "status-bar", "status_bar.zig", &.{});
    const power = feature(b, target, optimize, shared, "power", "power.zig", &.{.{ "command-palette", command_palette }});
    const explorer = feature(b, target, optimize, shared, "explorer", "explorer.zig", &.{.{ "command-palette", command_palette }});
    const search = feature(b, target, optimize, shared, "search", "search.zig", &.{.{ "command-palette", command_palette }});
    const spaces = feature(b, target, optimize, shared, "spaces", "spaces.zig", &.{ .{ "command-palette", command_palette }, .{ "tabs", tabs } });
    const settings = feature(b, target, optimize, shared, "settings", "settings.zig", &.{});
    const shortcuts = feature(b, target, optimize, shared, "shortcuts", "shortcuts.zig", &.{.{ "command-palette", command_palette }});
    const source_control = feature(b, target, optimize, shared, "source-control", "source_control.zig", &.{ .{ "tabs", tabs }, .{ "command-palette", command_palette } });
    const git_history = feature(b, target, optimize, shared, "git-history", "git_history.zig", &.{ .{ "tabs", tabs }, .{ "command-palette", command_palette } });
    const viewer_uses = [_]struct { []const u8, *std.Build.Module }{ .{ "tabs", tabs }, .{ "command-palette", command_palette }, .{ "webview", webview } };
    const preview = feature(b, target, optimize, shared, "preview", "preview.zig", &viewer_uses);
    const media_preview = feature(b, target, optimize, shared, "media-preview", "media_preview.zig", &viewer_uses);
    const markdown_rendered = feature(b, target, optimize, shared, "markdown-rendered", "markdown_rendered.zig", &viewer_uses);

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
            .{ .name = "strings", .module = strings },
            .{ .name = "command-palette", .module = command_palette },
            .{ .name = "shortcuts", .module = shortcuts },
            .{ .name = "themes", .module = themes },
            .{ .name = "settings", .module = settings },
            .{ .name = "terminal", .module = terminal },
            .{ .name = "tabs", .module = tabs },
            .{ .name = "editor", .module = editor },
            .{ .name = "markdown", .module = markdown },
            .{ .name = "status-bar", .module = status_bar },
            .{ .name = "power", .module = power },
            .{ .name = "explorer", .module = explorer },
            .{ .name = "search", .module = search },
            .{ .name = "spaces", .module = spaces },
            .{ .name = "source-control", .module = source_control },
            .{ .name = "git-history", .module = git_history },
            .{ .name = "webview", .module = webview },
            .{ .name = "preview", .module = preview },
            .{ .name = "media-preview", .module = media_preview },
            .{ .name = "markdown-rendered", .module = markdown_rendered },
        },
    });
    linkCore(root, b.pathFromRoot(core_lib));

    // The icon and the version Explorer shows; the version comes from the
    // Mac's Info.plist through packaging/build.sh, so both apps match.
    const version = b.option([]const u8, "version", "The app's version, x.y.z") orelse "0.0.0";
    root.addWin32ResourceFile(.{ .file = resourceScript(b, version) });

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
        .{ "app", root },                       .{ "ui", ui }, .{ "gfx", gfx }, .{ "icons", icons }, .{ "strings", strings }, .{ "win32", win32 },
        .{ "command-palette", command_palette }, .{ "shortcuts", shortcuts }, .{ "themes", themes }, .{ "settings", settings }, .{ "terminal", terminal }, .{ "tabs", tabs }, .{ "status-bar", status_bar }, .{ "power", power }, .{ "explorer", explorer }, .{ "search", search }, .{ "spaces", spaces }, .{ "editor", editor }, .{ "markdown", markdown },
        .{ "source-control", source_control }, .{ "git-history", git_history },
        .{ "webview", webview }, .{ "preview", preview }, .{ "media-preview", media_preview }, .{ "markdown-rendered", markdown_rendered },
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
    strings: *std.Build.Module,
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
            .{ .name = "strings", .module = shared.strings },
        },
    });
    for (uses) |entry| module.addImport(entry[0], entry[1]);
    linkCore(module, shared.core_lib);
    return module;
}

/// Cadex.rc for `version`, next to a copy of the icon (an .rc names its
/// files relative to itself).
fn resourceScript(b: *std.Build, version: []const u8) std.Build.LazyPath {
    var parts: [3]u16 = .{ 0, 0, 0 };
    var it = std.mem.tokenizeScalar(u8, version, '.');
    for (&parts) |*part| part.* = std.fmt.parseInt(u16, it.next() orelse "0", 10) catch 0;
    const files = b.addWriteFiles();
    _ = files.addCopyFile(b.path("app/Cadex.ico"), "Cadex.ico");
    return files.add("Cadex.rc", b.fmt(
        \\1 ICON "Cadex.ico"
        \\1 VERSIONINFO
        \\FILEVERSION {d},{d},{d},0
        \\PRODUCTVERSION {d},{d},{d},0
        \\BEGIN
        \\  BLOCK "StringFileInfo"
        \\  BEGIN
        \\    BLOCK "041604B0"
        \\    BEGIN
        \\      VALUE "CompanyName", "Cadex"
        \\      VALUE "FileDescription", "Cadex"
        \\      VALUE "FileVersion", "{s}"
        \\      VALUE "ProductName", "Cadex"
        \\      VALUE "ProductVersion", "{s}"
        \\      VALUE "LegalCopyright", "MIT"
        \\      VALUE "OriginalFilename", "Cadex.exe"
        \\    END
        \\  END
        \\  BLOCK "VarFileInfo"
        \\  BEGIN
        \\    VALUE "Translation", 0x0416, 1200
        \\  END
        \\END
        \\
    , .{ parts[0], parts[1], parts[2], parts[0], parts[1], parts[2], version, version }));
}
