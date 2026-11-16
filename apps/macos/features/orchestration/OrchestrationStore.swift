import Foundation
import SQLite3

/// The orchestration's state on disk: the system's SQLite (no new
/// dependency, ADR 0007), in
/// ~/Library/Application Support/Cadex/orchestration/state.sqlite. One
/// table per kind of record, each row the record as JSON plus its parent's
/// id (a contender's race, a task's run, an automation run's automation),
/// indexed, so a page reads one race or run without the rest. Opened only
/// with the feature on (OrchestrationController). Not thread-safe: one
/// owner, the main actor.
public final class OrchestrationStore {
    /// The tables, each with the parent it is read by.
    public enum Table: String, CaseIterable, Sendable {
        case races, contenders, runs, tasks, dispatches, messages, automations, automationRuns
    }

    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Opens or creates the file (0600, its folder 0700); ":memory:" for tests.
    public init(path: String) throws {
        if path != ":memory:" {
            let folder = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw OrchestrationStoreError.open(path)
        }
        if path != ":memory:" { chmod(path, 0o600) }
        var schema = "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;"
        for table in Table.allCases {
            schema += """
                CREATE TABLE IF NOT EXISTS \(table.rawValue)(id TEXT PRIMARY KEY, parent TEXT NOT NULL, json BLOB NOT NULL);
                CREATE INDEX IF NOT EXISTS \(table.rawValue)_parent ON \(table.rawValue)(parent);
                """
        }
        try exec(schema)
    }

    deinit { sqlite3_close(db) }

    /// Writes `record` under `id`, read back by `parent` ("" for a top one).
    public func put<T: Encodable>(_ table: Table, id: String, parent: String = "", _ record: T) throws {
        let json = try encoder.encode(record)
        try run("INSERT INTO \(table.rawValue)(id, parent, json) VALUES(?, ?, ?) ON CONFLICT(id) DO UPDATE SET parent = excluded.parent, json = excluded.json",
                [.text(id), .text(parent), .blob(json)])
    }

    public func get<T: Decodable>(_ table: Table, id: String, as type: T.Type = T.self) throws -> T? {
        try rows("SELECT json FROM \(table.rawValue) WHERE id = ?", [.text(id)]).first.map { try decoder.decode(T.self, from: $0) }
    }

    /// The records under `parent`, or every one of the table with nil. A row
    /// that no longer decodes (a field renamed by a newer Cadex) is skipped.
    public func all<T: Decodable>(_ table: Table, parent: String? = nil, as type: T.Type = T.self) throws -> [T] {
        let found = try parent.map { try rows("SELECT json FROM \(table.rawValue) WHERE parent = ? ORDER BY rowid", [.text($0)]) }
            ?? rows("SELECT json FROM \(table.rawValue) ORDER BY rowid", [])
        return found.compactMap { try? decoder.decode(T.self, from: $0) }
    }

    public func delete(_ table: Table, id: String) throws {
        try run("DELETE FROM \(table.rawValue) WHERE id = ?", [.text(id)])
    }

    /// Many changes in one transaction: all of them, or none when one throws.
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
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw OrchestrationStoreError.sql(String(cString: sqlite3_errmsg(db))) }
    }

    private func run(_ sql: String, _ values: [Value]) throws { _ = try rows(sql, values) }

    /// The first column of each row, as bytes.
    private func rows(_ sql: String, _ values: [Value]) throws -> [Data] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw OrchestrationStoreError.sql(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(stmt) }
        // SQLITE_TRANSIENT: SQLite copies the bytes before the call returns.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let at = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(stmt, at, text, -1, transient)
            case .blob(let data): _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, at, $0.baseAddress, Int32(data.count), transient) }
            }
        }
        var out: [Data] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return out }
            guard step == SQLITE_ROW else { throw OrchestrationStoreError.sql(String(cString: sqlite3_errmsg(db))) }
            if sqlite3_column_count(stmt) > 0, let bytes = sqlite3_column_blob(stmt, 0) {
                out.append(Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
            }
        }
    }
}

public enum OrchestrationStoreError: Error, Equatable {
    case open(String)
    case sql(String)
}
