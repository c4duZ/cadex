import AppKit
import CCadex

/// One row of a folder listing, from the core (core/features/explorer/listing.zig).
struct FileEntry: Equatable {
    enum Kind: UInt8 { case file = 0, directory = 1, symlink = 2, other = 3 }

    let name: String
    let kind: Kind
    let size: UInt64
    let linkToDirectory: Bool
    /// Left out by .gitignore, .ignore or .git/info/exclude: shown dimmed.
    var ignored = false

    var opensAsFolder: Bool { kind == .directory || linkToDirectory }
}

/// Why a file operation was refused, in the words the explorer shows.
struct ExplorerError: Error, Equatable {
    let status: cadex_status

    var message: String {
        switch status {
        case CADEX_ALREADY_EXISTS: "Já existe um item com esse nome"
        case CADEX_NOT_AUTHORIZED: "Fora da pasta aberta"
        case CADEX_NOT_FOUND: "O item não existe mais"
        case CADEX_PERMISSION_DENIED: "Sem permissão"
        case CADEX_INVALID_ARGUMENT: "Nome ou destino inválido"
        default: "A operação falhou"
        }
    }
}

/// The explorer's calls into the core: every disk access goes through here
/// (the core checks the workspace on each). Trash is the system's.
enum ExplorerFiles {
    static func list(_ path: String) throws(ExplorerError) -> [FileEntry] {
        var listing = cadex_explorer_listing()
        let status = cadex_explorer_list(path, &listing)
        guard status == CADEX_OK else { throw ExplorerError(status: status) }
        defer { cadex_explorer_listing_free(&listing) }
        guard let entries = listing.entries, let names = listing.names else { return [] }
        return (0..<listing.count).map { i in
            let e = entries[i]
            let name = String(decoding: UnsafeBufferPointer(start: names + Int(e.name_offset), count: Int(e.name_len)), as: UTF8.self)
            return FileEntry(name: name, kind: FileEntry.Kind(rawValue: e.kind) ?? .other, size: e.size,
                             linkToDirectory: e.link_to_directory, ignored: e.ignored)
        }
    }

    static func createFile(_ path: String) throws(ExplorerError) {
        try check(cadex_explorer_create_file(path))
    }

    static func createDirectory(_ path: String) throws(ExplorerError) {
        try check(cadex_explorer_create_directory(path))
    }

    /// The new path.
    static func rename(_ path: String, to name: String) throws(ExplorerError) -> String {
        try pathResult { cadex_explorer_rename(path, name, &$0, &$1) }
    }

    static func move(_ path: String, into folder: String) throws(ExplorerError) -> String {
        try pathResult { cadex_explorer_move(path, folder, &$0, &$1) }
    }

    static func copy(_ path: String, into folder: String) throws(ExplorerError) -> String {
        try pathResult { cadex_explorer_copy(path, folder, &$0, &$1) }
    }

    /// To the system Trash, never deleted for good (docs/spec/explorer.md).
    /// The folder holding it must be inside the workspace; the item itself
    /// may be a link pointing anywhere, which the Trash moves as a link.
    static func trash(_ path: String) throws(ExplorerError) {
        let parent = (path as NSString).deletingLastPathComponent
        guard cadex_workspace_is_authorized(parent) else { throw ExplorerError(status: CADEX_NOT_AUTHORIZED) }
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        } catch {
            throw ExplorerError(status: CADEX_IO_FAILED)
        }
    }

    private static func check(_ status: cadex_status) throws(ExplorerError) {
        guard status == CADEX_OK else { throw ExplorerError(status: status) }
    }

    private static func pathResult(
        _ call: (inout UnsafeMutablePointer<UInt8>?, inout Int) -> cadex_status
    ) throws(ExplorerError) -> String {
        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        try check(call(&bytes, &length))
        guard let bytes else { return "" }
        defer { cadex_free(bytes) }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    }
}
