import AppKit

/// A file's icon and its color by name and extension, for every place that
/// shows files: the explorer's tree and the tabs (moved here from the
/// explorer when the tabs needed them, 2026-10-19). Phosphor glyphs
/// (docs/spec/explorer.md: code, Markdown, image, video, audio, PDF,
/// archive, config, other).
public enum FileIcons {
    public static func icon(forFileNamed name: String) -> Icon {
        let lower = name.lowercased()
        if let special = iconsByName[lower] { return special }
        guard let dot = lower.lastIndex(of: "."), dot != lower.startIndex else { return .file }
        return iconsByExtension[String(lower[lower.index(after: dot)...])] ?? .file
    }

    private static let iconsByName: [String: Icon] = [
        "makefile": .fileCode, "dockerfile": .fileCode, "license": .fileText, "notice": .fileText,
        ".gitignore": .bracketsCurly, ".env": .bracketsCurly, ".editorconfig": .bracketsCurly,
    ]

    private static let iconsByExtension: [String: Icon] = {
        var map: [String: Icon] = [:]
        let groups: [(Icon, [String])] = [
            (.fileCode, ["zig", "swift", "c", "h", "m", "mm", "cpp", "hpp", "cc", "rs", "go", "py", "rb", "js", "mjs",
                         "cjs", "ts", "tsx", "jsx", "java", "kt", "cs", "php", "lua", "sh", "zsh", "bash", "fish",
                         "sql", "html", "css", "scss", "vue", "svelte", "ex", "exs", "dart", "scala", "metal", "zon",
                         "modulemap", "gradle", "pl", "r"]),
            (.fileMd, ["md", "markdown", "mdx"]),
            (.fileText, ["txt", "rtf", "log", "csv", "tsv"]),
            (.bracketsCurly, ["json", "jsonc", "yaml", "yml", "toml", "ini", "xml", "plist", "lock", "conf", "cfg",
                              "env", "properties"]),
            (.fileImage, ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "tif", "svg", "ico", "icns", "ppm"]),
            (.fileVideo, ["mp4", "mov", "m4v", "webm", "mkv", "avi"]),
            (.fileAudio, ["mp3", "wav", "aac", "m4a", "flac", "ogg", "aiff"]),
            (.filePdf, ["pdf"]),
            (.fileArchive, ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "zst"]),
        ]
        for (icon, extensions) in groups { for ext in extensions { map[ext] = icon } }
        return map
    }()

    /// The color of a file's icon by type, so a folder of Swift reads at a
    /// glance. The groups follow CodeEdit's CEWorkspaceFileIcon.iconColor (MIT,
    /// see NOTICE), with Zig, Markdown and TOML added; anything else is the
    /// tree's gray (nil).
    public static func color(forFileNamed name: String) -> NSColor? {
        let lower = name.lowercased()
        if let special = colorsByName[lower] { return special }
        guard let dot = lower.lastIndex(of: "."), dot != lower.startIndex else { return nil }
        return colorsByExtension[String(lower[lower.index(after: dot)...])]
    }

    private static let amber = NSColor(srgbRed: 0.98, green: 0.72, blue: 0.13, alpha: 1)
    private static let scarlet = NSColor(srgbRed: 0.94, green: 0.33, blue: 0.29, alpha: 1)

    private static let colorsByName: [String: NSColor] = [
        "makefile": NSColor(srgbRed: 0.937, green: 0.325, blue: 0.314, alpha: 1),
        "license": amber, "package.resolved": scarlet,
    ]

    private static let colorsByExtension: [String: NSColor] = {
        var map: [String: NSColor] = [:]
        let groups: [(NSColor, [String])] = [
            (.systemOrange, ["swift", "html", "rs"]),
            (.systemBlue, ["java", "jpg", "jpeg", "png", "svg", "ts", "md", "markdown", "mdx"]),
            (.systemTeal, ["css", "scss"]),
            (amber, ["js", "mjs", "cjs", "py", "entitlements", "zig", "zon"]),
            (scarlet, ["json", "jsonc", "rb", "strings", "yml", "yaml", "toml"]),
            (.systemCyan, ["jsx", "tsx"]),
            (.systemPurple, ["c", "cpp", "cc", "hpp"]),
            (NSColor(srgbRed: 0.255, green: 0.722, blue: 0.514, alpha: 1), ["vue"]),
            (NSColor(srgbRed: 0.667, green: 0.031, blue: 0.133, alpha: 1), ["h"]),
            (NSColor(srgbRed: 0.45, green: 0.3, blue: 0.75, alpha: 1), ["m", "mm"]),
            (NSColor(srgbRed: 0.02, green: 0.675, blue: 0.757, alpha: 1), ["go"]),
            (NSColor(srgbRed: 0.925, green: 0.251, blue: 0.478, alpha: 1), ["sum", "mod"]),
        ]
        for (color, extensions) in groups { for ext in extensions { map[ext] = color } }
        return map
    }()
}
