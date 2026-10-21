import Foundation

/// A server from ~/.ssh/config (docs/spec/ssh.md): a Host with a fixed
/// name, where it really is, its port, and the proxy it is reached through.
public struct SSHHost: Equatable, Sendable {
    public let alias: String
    public let hostName: String
    public let port: UInt16
    /// ProxyJump or ProxyCommand: such a host is not tested straight (that
    /// would say "down" for one that works).
    public let proxy: String?
}

/// Reads ~/.ssh/config and what it includes. Pure on text, so the rules
/// are tested without a home folder.
public enum SSHConfig {
    /// The hosts in the file at `path`, Include files read where they are
    /// written (relative ones from ~/.ssh), at most 8 levels deep.
    public static func hosts(at path: String, home: String = NSHomeDirectory()) -> [SSHHost] {
        var seen = Set<String>()
        return read(path, home: home, depth: 0, seen: &seen)
    }

    static func read(_ path: String, home: String, depth: Int, seen: inout Set<String>) -> [SSHHost] {
        guard depth < 8, seen.insert(path).inserted, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var hosts: [SSHHost] = []
        var block = Block()
        func flush() {
            hosts += block.hosts()
            block = Block()
        }
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let (key, value) = split(line)
            switch key {
            case "host":
                flush()
                block.aliases = value.split(separator: " ").map(String.init)
            case "match":
                // A Match block is a rule, never a server of its own.
                flush()
            case "include":
                flush()
                for pattern in value.split(separator: " ") {
                    for file in expand(String(pattern), home: home) { hosts += read(file, home: home, depth: depth + 1, seen: &seen) }
                }
            case "hostname": block.hostName = value
            case "port": block.port = UInt16(value)
            case "proxyjump", "proxycommand": block.proxy = value
            default: break
            }
        }
        flush()
        return hosts
    }

    /// "Key value", "Key=value" or "Key = value", the key without case.
    static func split(_ line: String) -> (String, String) {
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "="))
        guard let cut = line.rangeOfCharacter(from: separators) else { return (line.lowercased(), "") }
        let key = line[..<cut.lowerBound].lowercased()
        let value = line[cut.upperBound...].trimmingCharacters(in: separators).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (key, value)
    }

    /// An Include pattern as files: ~ is home, a relative one starts at
    /// ~/.ssh, and * or ? match names in that folder.
    static func expand(_ pattern: String, home: String) -> [String] {
        var path = pattern.hasPrefix("~") ? home + pattern.dropFirst() : pattern
        if !path.hasPrefix("/") { path = home + "/.ssh/" + path }
        guard path.contains("*") || path.contains("?") else { return [path] }
        let folder = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return files.filter { fnmatch(name, $0, 0) == 0 }.sorted().map { folder + "/" + $0 }
    }

    /// One Host block as it is read.
    struct Block {
        var aliases: [String] = []
        var hostName: String?
        var port: UInt16?
        var proxy: String?

        /// A server per fixed name; *, ? and !negated names are rules.
        func hosts() -> [SSHHost] {
            aliases.filter { !$0.contains("*") && !$0.contains("?") && !$0.hasPrefix("!") }.map { alias in
                // %h is the alias itself.
                let name = (hostName ?? alias).replacingOccurrences(of: "%h", with: alias)
                return SSHHost(alias: alias, hostName: name, port: port ?? 22, proxy: proxy)
            }
        }
    }
}
