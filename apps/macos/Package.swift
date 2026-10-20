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
            exclude: ["CLAUDE.md", "Resources/LICENSE-Phosphor.txt", "Resources/LICENSE-MaterialIconTheme.txt", "tests"],
            resources: [.copy("Resources/Phosphor-Regular.ttf"), .copy("Resources/Phosphor-Fill.ttf"), .copy("Resources/FileIcons")]
        ),
        // The interface's texts in English or Portuguese (ADR 0015).
        .target(
            name: "Strings",
            path: "shared/strings",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        // The popup menus in the look of ⌘K (right click, "+", status bar).
        .target(
            name: "Menus",
            dependencies: ["Icons", "Strings"],
            path: "shared/menus",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "Power",
            dependencies: ["CommandPalette", "Strings"],
            path: "features/power",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "Themes",
            dependencies: ["Strings"],
            path: "features/themes",
            exclude: ["CLAUDE.md", "tests"],
            resources: [.copy("Resources/catalog.json")],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "Settings",
            dependencies: ["Themes", "CommandPalette", "Shortcuts", "Icons", "Strings"],
            path: "features/settings",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "StatusBar",
            dependencies: ["Icons", "Menus", "Strings"],
            path: "features/status-bar",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "CommandPalette",
            dependencies: ["CCadex", "Icons", "Menus", "Strings"],
            path: "features/command-palette",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "Shortcuts",
            dependencies: ["CommandPalette", "Strings"],
            path: "features/shortcuts",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "Terminal",
            dependencies: ["CCadex", "CommandPalette", "Icons", "Menus", "Strings"],
            path: "features/terminal",
            exclude: ["CLAUDE.md", "tests"],
            // @testable access for the feature's test executable.
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Tabs",
            dependencies: ["Terminal", "CommandPalette", "Icons", "Menus", "Strings"],
            path: "features/tabs",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Explorer",
            dependencies: ["CCadex", "CommandPalette", "Icons", "Menus", "Strings"],
            path: "features/explorer",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Search",
            dependencies: ["CCadex", "CommandPalette", "Icons", "Strings"],
            path: "features/search",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Editor",
            dependencies: ["CCadex", "CommandPalette", "Icons", "Tabs", "Strings"],
            path: "features/editor",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Markdown",
            dependencies: ["CCadex", "CommandPalette", "Editor", "Icons", "Menus", "Strings"],
            path: "features/markdown",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "MediaPreview",
            dependencies: ["CCadex", "CommandPalette", "Tabs", "Strings"],
            path: "features/media-preview",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "Preview",
            dependencies: ["CommandPalette", "Icons", "Menus", "Tabs", "Strings"],
            path: "features/preview",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .target(
            name: "Spaces",
            dependencies: ["CommandPalette", "Tabs", "Icons", "Strings"],
            path: "features/spaces",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "GitHistory",
            dependencies: ["CCadex", "CommandPalette", "Icons", "Menus", "Tabs", "Strings"],
            path: "features/git-history",
            exclude: ["CLAUDE.md", "tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .target(
            name: "SourceControl",
            dependencies: ["CCadex", "CommandPalette", "Icons", "Menus", "Editor", "Tabs", "Strings"],
            path: "features/source-control",
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
            dependencies: ["Shortcuts", "CommandPalette", "Terminal", "Tabs", "Explorer", "Search", "Editor", "Markdown", "MediaPreview", "Preview", "SourceControl", "GitHistory", "Spaces", "Checks"],
            path: "features/shortcuts/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),

        .executableTarget(
            name: "TabsTests",
            dependencies: ["Tabs", "Icons", "Checks"],
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
            name: "MarkdownTests",
            dependencies: ["Markdown", "Editor", "Explorer", "CommandPalette", "Checks"],
            path: "features/markdown/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "MediaPreviewTests",
            dependencies: ["MediaPreview", "Explorer", "Checks"],
            path: "features/media-preview/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "PreviewTests",
            dependencies: ["Preview", "Checks"],
            path: "features/preview/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "SpacesTests",
            dependencies: ["Spaces", "Tabs", "Checks"],
            path: "features/spaces/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "GitHistoryTests",
            dependencies: ["GitHistory", "Explorer", "Checks"],
            path: "features/git-history/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "SourceControlTests",
            dependencies: ["SourceControl", "Explorer", "CommandPalette", "Checks"],
            path: "features/source-control/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "PowerTests",
            dependencies: ["Power", "Checks"],
            path: "features/power/tests",
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
        .executableTarget(
            name: "StringsTests",
            dependencies: ["Strings", "Checks"],
            path: "shared/strings/tests"
        ),
        .executableTarget(
            name: "MenusTests",
            dependencies: ["Menus", "Checks"],
            path: "shared/menus/tests"
        ),
        .executableTarget(
            name: "IconsTests",
            dependencies: ["Icons", "Checks"],
            path: "shared/icons/tests"
        ),

        .executableTarget(
            name: "Cadex",
            dependencies: ["Terminal", "CommandPalette", "Shortcuts", "Tabs", "Themes", "StatusBar", "Icons", "Settings", "Explorer", "Search", "Editor", "Markdown", "MediaPreview", "Preview", "SourceControl", "GitHistory", "Spaces", "Menus", "Power", "Strings"],
            path: "app",
            exclude: ["CLAUDE.md"],
            linkerSettings: [.unsafeFlags(["-L", coreLibDir])]
        ),
    ]
)
