import Foundation
import TextIndex

/// The history's index on disk (docs/spec/agents.md, Histórico): every
/// account's transcripts (`<account>/projects/*/*.jsonl`, not the
/// subagents'), each a record with how far it was read plus its texts to
/// search, in one SQLite file (TextIndex). A refresh reads only what grew;
/// a file that shrank is read again; a file that left is forgotten.
/// One serial queue owns it; nothing here touches the main thread.
public final class AgentHistoryStore: @unchecked Sendable {
    private let index: TextIndex?
    let queue = DispatchQueue(label: "cadex.agents.history", qos: .utility)

    public init(path: String) {
        index = try? TextIndex(path: path)
    }

    /// The file: Cadex's own folder in Application Support (CADEX_PERF_HOME's in perf).
    public static func file(home: String) -> String {
        home + "/Library/Application Support/Cadex/history.sqlite"
    }

    /// On the queue: brings the index up to the disk and returns every entry.
    /// `progress` hears files done of the total, every 20 files read.
    public func refresh(accounts: [AgentAccount], progress: (Int, Int) -> Void = { _, _ in }) -> [AgentHistoryEntry] {
        guard let index else { return [] }
        var known: [String: AgentHistoryEntry] = [:]
        for (id, json) in (try? index.records()) ?? [] {
            if let entry = try? JSONDecoder().decode(AgentHistoryEntry.self, from: json) { known[id] = entry }
        }
        let files = Self.transcripts(accounts.filter { $0.provider == .claude })
        try? index.batch {
            for (done, (path, account)) in files.enumerated() {
                if done % 20 == 0 { progress(done, files.count) }
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
                var entry = known[path] ?? AgentHistoryEntry(id: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                                                            path: path, account: account)
                guard size != entry.offset else { continue }
                if size < entry.offset {
                    try index.remove(path)
                    entry = AgentHistoryEntry(id: entry.id, path: path, account: account)
                }
                for text in AgentHistoryReader.readNew(&entry) { try index.addText(path, text) }
                if let origin = entry.origin, entry.originPath == nil {
                    entry.originPath = files.first { ($0.path as NSString).lastPathComponent == origin + ".jsonl" }?.path
                }
                try index.setRecord(path, try JSONEncoder().encode(entry))
                known[path] = entry
            }
            let present = Set(files.map(\.path))
            for gone in known.keys where !present.contains(gone) {
                try index.remove(gone)
                known[gone] = nil
            }
        }
        return Array(known.values)
    }

    /// On the queue: the paths whose texts hold every word.
    public func search(_ words: String) -> Set<String> {
        Set((try? index?.search(words)) ?? [])
    }

    /// Every transcript of the accounts, with its account.
    static func transcripts(_ accounts: [AgentAccount]) -> [(path: String, account: String)] {
        let fm = FileManager.default
        var out: [(String, String)] = []
        for account in accounts {
            let projects = account.dir + "/projects"
            for folder in (try? fm.contentsOfDirectory(atPath: projects)) ?? [] {
                let dir = projects + "/" + folder
                for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".jsonl") {
                    out.append((dir + "/" + name, account.dir))
                }
            }
        }
        return out
    }
}
