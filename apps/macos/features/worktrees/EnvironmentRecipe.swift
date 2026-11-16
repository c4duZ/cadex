import Foundation

/// A repository's recipe for a task's throwaway environment, its
/// `.cadex/environment.toml` (docs/adr/0032-workspace-recipes.md):
///
///     image = "ubuntu:24.04"          # or dockerfile = "Dockerfile.dev"
///     machine = "pc"                  # where "Run on" starts; empty: ask
///     ports = [3000, 5173]
///     setup = "apt-get update && apt-get install -y nodejs"
///     workdir = "/work"
///     [tailscale]
///     name = "ubuntu-dev"
///     authkey_env = "TS_AUTHKEY"      # the variable's name, never the key
public struct EnvironmentRecipe: Equatable, Sendable {
    public var image = ""
    public var dockerfile = ""
    public var machine = ""
    public var ports: [Int] = []
    public var setup = ""
    public var workdir = "/work"
    /// The sidecar's machine name on the tailnet; empty: no sidecar.
    public var tailscaleName = ""
    public var authKeyVariable = "TS_AUTHKEY"

    public static let file = ".cadex/environment.toml"

    /// The recipe of `repo`, nil when it has none; a recipe that does not
    /// read is an error with its line, never half a recipe.
    public static func load(repo: String) -> Result<EnvironmentRecipe, RecipeError>? {
        guard let text = try? String(contentsOfFile: repo + "/" + file, encoding: .utf8) else { return nil }
        return parse(text)
    }

    public static func parse(_ text: String) -> Result<EnvironmentRecipe, RecipeError> {
        var recipe = EnvironmentRecipe()
        var table = ""
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = TOMLLine.strip(String(raw))
            if line.isEmpty { continue }
            let number = index + 1
            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), !line.hasPrefix("[[") else { return .failure(RecipeError(line: number, message: "a table is [name]")) }
                table = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard table == "tailscale" else { return .failure(RecipeError(line: number, message: "unknown table [\(table)]")) }
                continue
            }
            guard let equal = line.firstIndex(of: "=") else { return .failure(RecipeError(line: number, message: "expected key = value")) }
            let key = line[..<equal].trimmingCharacters(in: .whitespaces)
            let rest = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            guard let value = TOMLLine.value(rest) else { return .failure(RecipeError(line: number, message: "\(key): a value TOML reads")) }
            if let problem = recipe.set(table.isEmpty ? key : table + "." + key, value) {
                return .failure(RecipeError(line: number, message: problem))
            }
        }
        if recipe.image.isEmpty == recipe.dockerfile.isEmpty {
            return .failure(RecipeError(line: 0, message: "either image or dockerfile, one of them"))
        }
        return .success(recipe)
    }

    private mutating func set(_ key: String, _ value: TOMLValue) -> String? {
        switch (key, value) {
        case ("image", .text(let v)): image = v
        case ("dockerfile", .text(let v)): dockerfile = v
        case ("machine", .text(let v)): machine = v
        case ("setup", .text(let v)): setup = v
        case ("workdir", .text(let v)): workdir = v
        case ("tailscale.name", .text(let v)): tailscaleName = v
        case ("tailscale.authkey_env", .text(let v)):
            guard v.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), !v.isEmpty else { return "authkey_env is a variable's name" }
            authKeyVariable = v
        case ("ports", .list(let items)):
            let numbers = items.compactMap { if case .number(let n) = $0, (1...65535).contains(n) { n } else { nil } }
            guard numbers.count == items.count else { return "ports is a list of port numbers" }
            ports = numbers
        case ("image", _), ("dockerfile", _), ("machine", _), ("setup", _), ("workdir", _), ("tailscale.name", _), ("tailscale.authkey_env", _):
            return "\(key) is a text in quotes"
        case ("ports", _):
            return "ports is a list, [3000, 5173]"
        default:
            return "unknown key \(key)"
        }
        return nil
    }
}

public struct RecipeError: Error, Equatable, Sendable {
    /// 0: about the whole recipe.
    public let line: Int
    public let message: String

    public var description: String { line == 0 ? message : "line \(line): \(message)" }
}

enum TOMLValue: Equatable {
    case text(String), number(Int), bool(Bool), list([TOMLValue])
}

/// The bit of TOML a recipe needs: texts ("…" with \" \\ \n \t, '…' as
/// is), integers, true/false and one-line lists of those. No dependency
/// for this (the repository's rule); anything else is an error.
enum TOMLLine {
    /// The line without its comment (a # outside quotes) and spaces.
    static func strip(_ line: String) -> String {
        var quote: Character?
        var escaped = false
        for (offset, ch) in line.enumerated() {
            if escaped { escaped = false; continue }
            if quote == "\"", ch == "\\" { escaped = true; continue }
            if let open = quote { if ch == open { quote = nil }; continue }
            if ch == "\"" || ch == "'" { quote = ch; continue }
            if ch == "#" { return String(line.prefix(offset)).trimmingCharacters(in: .whitespaces) }
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    static func value(_ text: String) -> TOMLValue? {
        var rest = Substring(text)
        guard let value = parseValue(&rest), rest.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    private static func parseValue(_ rest: inout Substring) -> TOMLValue? {
        rest = rest.drop { $0 == " " }
        guard let first = rest.first else { return nil }
        if first == "\"" || first == "'" { return parseText(&rest, quote: first) }
        if first == "[" {
            rest = rest.dropFirst()
            var items: [TOMLValue] = []
            while true {
                rest = rest.drop { $0 == " " }
                if rest.first == "]" { rest = rest.dropFirst(); return .list(items) }
                guard let item = parseValue(&rest) else { return nil }
                items.append(item)
                rest = rest.drop { $0 == " " }
                if rest.first == "," { rest = rest.dropFirst() } else if rest.first != "]" { return nil }
            }
        }
        let word = rest.prefix { $0 != "," && $0 != "]" && $0 != " " }
        rest = rest.dropFirst(word.count)
        if word == "true" { return .bool(true) }
        if word == "false" { return .bool(false) }
        return Int(word.replacingOccurrences(of: "_", with: "")).map(TOMLValue.number)
    }

    private static func parseText(_ rest: inout Substring, quote: Character) -> TOMLValue? {
        rest = rest.dropFirst()
        var out = ""
        while let ch = rest.first {
            rest = rest.dropFirst()
            if ch == quote { return .text(out) }
            if quote == "\"", ch == "\\" {
                guard let next = rest.first else { return nil }
                rest = rest.dropFirst()
                switch next {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "\"", "\\": out.append(next)
                default: return nil
                }
            } else {
                out.append(ch)
            }
        }
        return nil
    }
}
