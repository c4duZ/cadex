import Foundation
import SQLite3

/// Full-text search over records, in one SQLite file with FTS5: the
/// system's own SQLite (macOS 13+ ships it with FTS5; checked with 3.54 on
/// 2026-11-14), so no new dependency (ADR 0007). Used by the agents'
/// history (plan 18, phase D) and later the memory (plan 22).
///
/// Three things per id: a record (JSON the caller owns), any number of
/// text pieces to search (FTS5 rows, so a growing document is added to,
/// never rewritten), and a free key-value table for the caller's
/// bookkeeping (read offsets). Not thread-safe: one owner, one queue.
public final class TextIndex {
    private var db: OpaquePointer?

    /// Opens or creates the file; ":memory:" for tests.
    public init(path: String) throws {
        if path != ":memory:" {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            throw TextIndexError.open(path)
        }
        try exec("""
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            CREATE TABLE IF NOT EXISTS records(id TEXT PRIMARY KEY, json BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE VIRTUAL TABLE IF NOT EXISTS texts USING fts5(id UNINDEXED, body, tokenize='unicode61 remove_diacritics 2');
            """)
    }

    deinit { sqlite3_close(db) }

    // MARK: Records

    public func setRecord(_ id: String, _ json: Data) throws {
        try run("INSERT INTO records(id, json) VALUES(?, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json", [.text(id), .blob(json)])
    }

    public func record(_ id: String) throws -> Data? {
        try query("SELECT json FROM records WHERE id = ?", [.text(id)]) { $0.blob(0) }.first
    }

    public func records() throws -> [(id: String, json: Data)] {
        try query("SELECT id, json FROM records", []) { ($0.text(0), $0.blob(1)) }
    }

    /// The record, its texts and nothing else of it.
    public func remove(_ id: String) throws {
        try run("DELETE FROM records WHERE id = ?", [.text(id)])
        try run("DELETE FROM texts WHERE id = ?", [.text(id)])
    }

    // MARK: Texts

    public func addText(_ id: String, _ text: String) throws {
        guard !text.isEmpty else { return }
        try run("INSERT INTO texts(id, body) VALUES(?, ?)", [.text(id), .text(text)])
    }

    /// The ids whose texts hold every word of `words`, each as a prefix
    /// ("depl serv" finds "deploy no servidor"); accents and case ignored.
    public func search(_ words: String, limit: Int = 500) throws -> [String] {
        let terms = words.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { "\"" + $0 + "\"*" }
        guard !terms.isEmpty else { return [] }
        return try query("SELECT DISTINCT id FROM texts WHERE texts MATCH ? LIMIT ?", [.text(terms.joined(separator: " ")), .int(limit)]) { $0.text(0) }
    }

    // MARK: Meta

    public func meta(_ key: String) throws -> String? {
        try query("SELECT value FROM meta WHERE key = ?", [.text(key)]) { $0.text(0) }.first
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        if let value { try run("INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [.text(key), .text(value)]) }
        else { try run("DELETE FROM meta WHERE key = ?", [.text(key)]) }
    }

    /// Many changes in one transaction: one disk write instead of one each.
    public func batch(_ body: () throws -> Void) throws {
        try exec("BEGIN")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    // MARK: SQLite

    enum Value {
        case text(String)
        case blob(Data)
        case int(Int)
    }

    struct Row {
        let stmt: OpaquePointer?
        func text(_ column: Int32) -> String { sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? "" }
        func blob(_ column: Int32) -> Data {
            guard let bytes = sqlite3_column_blob(stmt, column) else { return Data() }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, column)))
        }
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw TextIndexError.sql(String(cString: sqlite3_errmsg(db))) }
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        _ = try query(sql, values) { _ in () }
    }

    private func query<T>(_ sql: String, _ values: [Value], _ row: (Row) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw TextIndexError.sql(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(stmt) }
        // SQLITE_TRANSIENT: SQLite copies the bytes before the call returns.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let at = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(stmt, at, text, -1, transient)
            case .blob(let data): _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, at, $0.baseAddress, Int32(data.count), transient) }
            case .int(let number): sqlite3_bind_int64(stmt, at, Int64(number))
            }
        }
        var out: [T] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW { out.append(row(Row(stmt: stmt))); continue }
            if step == SQLITE_DONE { return out }
            throw TextIndexError.sql(String(cString: sqlite3_errmsg(db)))
        }
    }
}

public enum TextIndexError: Error {
    case open(String)
    case sql(String)
}
