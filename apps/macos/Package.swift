// swift-tools-version: 6.0
//
// Each feature is its own Swift module: only what it marks `public` is
// visible to the others, so "use a feature only through its entry point"
// is enforced by the compiler (see ../../CLAUDE.md).

import PackageDescription

/// libcadex.a, built by `zig build` in core/ (run `make core` first).
let coreLibDir = Context.packageDirectory + "/../../core/zig-out/lib"

let package = Package(
    name: "Cadex",
    platforms: [.macOS(.v13)],
    targets: [
        // The core's C API (core/include/cadex.h) as a Swift module.
        .systemLibrary(name: "CCadex", path: "shared/core-bridge"),

        .target(
            name: "CommandPalette",
            path: "features/command-palette",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "Shortcuts",
            dependencies: ["CommandPalette"],
            path: "features/shortcuts",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "Terminal",
            dependencies: ["CCadex", "CommandPalette"],
            path: "features/terminal",
            exclude: ["CLAUDE.md", "tests"],
            // @testable access for the feature's test executable.
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        // Tests are an executable: see shared/checks/Checks.swift.
        .target(name: "Checks", path: "shared/checks"),
        .executableTarget(
            name: "TerminalTests",
            dependencies: ["Terminal", "Checks"],
            path: "features/terminal/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),

        .executableTarget(
            name: "CommandPaletteTests",
            dependencies: ["CommandPalette", "Checks"],
            path: "features/command-palette/tests"
        ),
        // Shortcuts tests check the defaults of every feature's commands.
        .executableTarget(
            name: "ShortcutsTests",
            dependencies: ["Shortcuts", "CommandPalette", "Terminal", "Checks"],
            path: "features/shortcuts/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),

        .executableTarget(
            name: "Cadex",
            dependencies: ["Terminal", "CommandPalette", "Shortcuts"],
            path: "app",
            exclude: ["CLAUDE.md"],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
    ]
)
