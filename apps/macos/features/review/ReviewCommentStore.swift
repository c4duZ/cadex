import Foundation

/// A worktree's comments on disk (docs/spec/review.md): the ones not sent
/// yet and the sent ones, in `<dir>/<repo>/<worktree>.json`, dir being
/// `~/Library/Application Support/Cadex/review` (CADEX_REVIEW_DIR for test
/// instances, like the other CADEX_ folders). Written on every change, so
/// they survive closing the app.
public struct ReviewCommentStore: Sendable {
    /// What went to the agent together, and when.
    public struct Sent: Codable, Equatable, Sendable {
        public var date: Date
        public var text: String
        public var comments: [ReviewComment]
    }

    struct File: Codable, Equatable {
        var pending: [ReviewComment] = []
        var sent: [Sent] = []
    }

    public let path: String

    public init(repo: String, worktree: String, dir: String? = nil) {
        let root = dir ?? ProcessInfo.processInfo.environment["CADEX_REVIEW_DIR"]
            ?? (NSHomeDirectory() + "/Library/Application Support/Cadex/review")
        path = root + "/" + Self.safe(repo) + "/" + Self.safe(worktree) + ".json"
    }

    /// A folder or file name from any text: no slash, no leading dot.
    static func safe(_ name: String) -> String {
        let cleaned = name.map { $0 == "/" || $0 == ":" ? "-" : $0 }
        let text = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return text.isEmpty ? "_" : text
    }

    func read() -> File {
        guard let data = FileManager.default.contents(atPath: path) else { return File() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(File.self, from: data)) ?? File()
    }

    func write(_ file: File) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
