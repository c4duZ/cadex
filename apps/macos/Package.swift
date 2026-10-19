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

        // Phosphor icons for every feature (docs/adr/0008-phosphor-icons.md).
        .target(
            name: "Icons",
            path: "shared/icons",
            exclude: ["CLAUDE.md", "Resources/LICENSE-Phosphor.txt", "tests"],
            resources: [.copy("Resources/Phosphor-Regular.ttf")]
        ),
        .target(
            name: "Themes",
            path: "features/themes",
            exclude: ["CLAUDE.md", "tests"],
            resources: [.copy("Resources/catalog.json")],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "Settings",
            dependencies: ["Themes", "CommandPalette", "Shortcuts", "Icons"],
            path: "features/settings",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "StatusBar",
            path: "features/status-bar",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "CommandPalette",
            dependencies: ["CCadex"],
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
            dependencies: ["CCadex", "CommandPalette", "Icons"],
            path: "features/terminal",
            exclude: ["CLAUDE.md", "tests"],
            // @testable access for the feature's test executable.
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Tabs",
            dependencies: ["Terminal", "CommandPalette", "Icons"],
            path: "features/tabs",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Explorer",
            dependencies: ["CCadex", "CommandPalette", "Icons"],
            path: "features/explorer",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Search",
            dependencies: ["CCadex", "CommandPalette"],
            path: "features/search",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Editor",
            dependencies: ["CCadex", "CommandPalette", "Icons", "Tabs"],
            path: "features/editor",
            exclude: ["CLAUDE.md", "tests"],
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
            path: "features/command-palette/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        // Shortcuts tests check the defaults of every feature's commands.
        .executableTarget(
            name: "ShortcutsTests",
            dependencies: ["Shortcuts", "CommandPalette", "Terminal", "Tabs", "Explorer", "Search", "Checks"],
            path: "features/shortcuts/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),

        .executableTarget(
            name: "TabsTests",
            dependencies: ["Tabs", "Checks"],
            path: "features/tabs/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),

        .executableTarget(
            name: "StatusBarTests",
            dependencies: ["StatusBar", "Checks"],
            path: "features/status-bar/tests"
        ),
        .executableTarget(
            name: "SettingsTests",
            dependencies: ["Settings", "Checks"],
            path: "features/settings/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "ThemesTests",
            dependencies: ["Themes", "Checks"],
            path: "features/themes/tests"
        ),
        .executableTarget(
            name: "ExplorerTests",
            dependencies: ["Explorer", "Icons", "CCadex", "Checks"],
            path: "features/explorer/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "SearchTests",
            dependencies: ["Search", "Explorer", "CommandPalette", "CCadex", "Checks"],
            path: "features/search/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "EditorTests",
            dependencies: ["Editor", "Explorer", "CCadex", "Checks"],
            path: "features/editor/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "IconsTests",
            dependencies: ["Icons", "Checks"],
            path: "shared/icons/tests"
        ),

        .executableTarget(
            name: "Cadex",
            dependencies: ["Terminal", "CommandPalette", "Shortcuts", "Tabs", "Themes", "StatusBar", "Icons", "Settings", "Explorer", "Search", "Editor"],
            path: "app",
            exclude: ["CLAUDE.md"],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
    ]
)
