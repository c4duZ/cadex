import Foundation

/// The automations as text (docs/spec/orchestration.md, "O estado"): one JSON per automation in
/// `orchestration/automations/<id>.json`, keys sorted and dates in ISO 8601, so the owner or an
/// agent reads and edits them (the owner, 2026-11-22; they lived as rows of state.sqlite, which no
/// one could edit). The file's name is the id. A file that does not read is left out and logged;
/// the others count. Their history stays in the database: it is a record, not configuration.
public struct AutomationFiles {
    public let folder: String

    public init(folder: String) { self.folder = folder }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func path(_ id: String) -> String { folder + "/" + id + ".json" }

    /// A name that is a file in the folder and nothing else: no "/", no "..".
    static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix(".") && !id.contains("/") && id.count <= 120
    }

    /// Every automation that reads, oldest file first (the order they were made).
    public func all() -> [Automation] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        let files = names.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.map { folder + "/" + $0 }
        func made(_ path: String) -> Date { (try? FileManager.default.attributesOfItem(atPath: path)[.creationDate] as? Date) ?? .distantPast }
        return files.map { ($0, made($0)) }.sorted { ($0.1, $0.0) < ($1.1, $1.0) }.compactMap { read($0.0) }
    }

    public func get(_ id: String) -> Automation? {
        guard Self.isSafe(id) else { return nil }
        return read(path(id))
    }

    /// The file's automation, its id from the file's name (a file written by hand may leave it out,
    /// or copy another's).
    func read(_ path: String) -> Automation? {
        let id = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AutomationFileError.notAnObject
            }
            object["id"] = id
            return try Self.decoder.decode(Automation.self, from: JSONSerialization.data(withJSONObject: object))
        } catch {
            NSLog("Cadex automations: %@ was left out (%@)", path, "\(error)")
            return nil
        }
    }

    /// Writes it whole, atomically (a reader never sees half a file).
    public func save(_ automation: Automation) throws {
        guard Self.isSafe(automation.id) else { throw AutomationFileError.badName(automation.id) }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        var data = try Self.encoder.encode(automation)
        data.append(0x0A)
        try data.write(to: URL(fileURLWithPath: path(automation.id)), options: .atomic)
    }

    public func delete(_ id: String) throws {
        guard Self.isSafe(id), FileManager.default.fileExists(atPath: path(id)) else { return }
        try FileManager.default.removeItem(atPath: path(id))
    }

    /// The automations of a database from before the files, written as files once and taken out
    /// of it; one already a file stays as the file says.
    public func migrate(from store: OrchestrationStore) {
        guard let old: [Automation] = try? store.all(.automations), !old.isEmpty else { return }
        for automation in old {
            if !FileManager.default.fileExists(atPath: path(automation.id)) {
                do { try save(automation) } catch {
                    NSLog("Cadex automations: %@ stayed in the database (%@)", automation.id, "\(error)")
                    continue
                }
            }
            try? store.delete(.automations, id: automation.id)
        }
    }
}

public enum AutomationFileError: Error, Equatable {
    case notAnObject
    case badName(String)
}
