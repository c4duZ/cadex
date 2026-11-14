import Foundation

/// The folder Claude Code keeps a working folder's conversations in, under
/// an account's projects/. Every character that is not an ASCII letter or
/// digit becomes "-"; a name longer than 200 keeps the first 200 and gets
/// "-" plus a hash of the original path in base 36 (Claude Code 2.1.325,
/// tested 2026-11-14: ".../a b_c.d-é" → "...-a-b-c-d--"; a 282-character
/// path → 200 + "-s3x6ke"). Cadex used to replace only "/" and ".", so
/// subagents and the reason of a stop went missing in folders with spaces,
/// "_" or accents (found by the test loop, 2026-11-14).
public enum AgentProjectFolder {
    static let limit = 200

    /// The folder's name for `cwd`.
    public static func name(for cwd: String) -> String {
        let encoded = String(String.UnicodeScalarView(cwd.unicodeScalars.map { isPlain($0) ? $0 : "-" }))
        guard encoded.count > limit else { return encoded }
        return String(encoded.prefix(limit)) + "-" + base36(hash(cwd))
    }

    /// The folder for `cwd` in `account`. A long name whose hash does not
    /// match a folder on disk (a hash rule Cadex has not seen) falls back to
    /// the one folder starting with the same 200 characters.
    public static func path(for cwd: String, in account: AgentAccount) -> String {
        let projects = account.dir + "/projects"
        let exact = projects + "/" + name(for: cwd)
        let encoded = name(for: cwd)
        guard encoded.count > limit, !FileManager.default.fileExists(atPath: exact) else { return exact }
        let prefix = String(encoded.prefix(limit)) + "-"
        let matches = ((try? FileManager.default.contentsOfDirectory(atPath: projects)) ?? []).filter { $0.hasPrefix(prefix) }
        return matches.count == 1 ? projects + "/" + matches[0] : exact
    }

    static func isPlain(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122: true
        default: false
        }
    }

    /// The 32-bit string hash Claude Code uses (h = 31·h + UTF-16 unit),
    /// as a non-negative number. Seen positive only; a negative one is
    /// taken by its absolute value, and `path` falls back if that is wrong.
    static func hash(_ text: String) -> UInt32 {
        var h: Int32 = 0
        for unit in text.utf16 { h = h &* 31 &+ Int32(unit) }
        return h == Int32.min ? UInt32(Int32.max) + 1 : UInt32(abs(h))
    }

    static func base36(_ value: UInt32) -> String { String(value, radix: 36) }
}
