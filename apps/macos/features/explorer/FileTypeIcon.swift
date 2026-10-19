import Icons

/// The Phosphor icon of a row, by kind and extension (docs/spec/explorer.md:
/// folder, code, Markdown, image, video, audio, PDF, archive, config, other).
enum FileTypeIcon {
    static func icon(name: String, entry: FileEntry?, expanded: Bool) -> Icon {
        guard let entry else { return expanded ? .folderOpen : .folder }
        if entry.opensAsFolder { return expanded ? .folderOpen : .folder }
        if entry.kind == .symlink { return .link }
        return icon(forFileNamed: name)
    }

    static func icon(forFileNamed name: String) -> Icon {
        let lower = name.lowercased()
        if let special = byName[lower] { return special }
        guard let dot = lower.lastIndex(of: "."), dot != lower.startIndex else { return .file }
        return byExtension[String(lower[lower.index(after: dot)...])] ?? .file
    }

    private static let byName: [String: Icon] = [
        "makefile": .fileCode, "dockerfile": .fileCode, "license": .fileText, "notice": .fileText,
        ".gitignore": .bracketsCurly, ".env": .bracketsCurly, ".editorconfig": .bracketsCurly,
    ]

    private static let byExtension: [String: Icon] = {
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
}
