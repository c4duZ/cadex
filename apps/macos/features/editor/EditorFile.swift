import Foundation
import CCadex
import Strings

/// Reading and saving the file through the core's explorer feature, which
/// checks the workspace (docs/spec/editor.md, "Limites").
enum EditorFile {
    /// Above this the editor shows the start only, read-only.
    static let maxBytes: UInt64 = 10 * 1024 * 1024
    /// Above this, no colors or folds (the core's limit too).
    static let maxHighlightBytes = 1024 * 1024

    enum Loaded: Equatable {
        /// `truncated`: only the first maxBytes. `valid`: the bytes were
        /// UTF-8 (otherwise bad bytes became U+FFFD and saving is off).
        case text(String, data: Data, truncated: Bool, valid: Bool)
        case binary
        case failed(String)
    }

    static func read(_ path: String) -> Loaded {
        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        var truncated = false
        let status = cadex_explorer_read_text_head(path, maxBytes, &bytes, &length, &truncated)
        switch status {
        case CADEX_OK: break
        case CADEX_BINARY: return .binary
        case CADEX_NOT_FOUND: return .failed(T("The file no longer exists", "O arquivo não existe mais"))
        case CADEX_NOT_AUTHORIZED: return .failed(T("The file is outside the open folder", "O arquivo está fora da pasta aberta"))
        case CADEX_PERMISSION_DENIED: return .failed(T("No permission to read the file", "Sem permissão para ler o arquivo"))
        default: return .failed(T("Couldn't read the file", "Não foi possível ler o arquivo"))
        }
        guard let bytes else { return .text("", data: Data(), truncated: false, valid: true) }
        defer { cadex_free(bytes) }
        let data = Data(bytes: bytes, count: length)
        if let text = String(data: data, encoding: .utf8) {
            return .text(text, data: data, truncated: truncated, valid: true)
        }
        return .text(String(decoding: data, as: UTF8.self), data: data, truncated: truncated, valid: false)
    }

    /// Nil when saved, otherwise why not.
    static func write(_ path: String, _ data: Data) -> String? {
        let status = data.withUnsafeBytes {
            cadex_explorer_write_text(path, $0.bindMemory(to: UInt8.self).baseAddress, data.count)
        }
        switch status {
        case CADEX_OK: return nil
        case CADEX_NOT_AUTHORIZED: return T("The file is outside the open folder", "O arquivo está fora da pasta aberta")
        case CADEX_PERMISSION_DENIED: return T("No permission to write the file", "Sem permissão para gravar o arquivo")
        default: return T("Couldn't save the file", "Não foi possível salvar o arquivo")
        }
    }
}
