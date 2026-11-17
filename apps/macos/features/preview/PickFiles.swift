import Foundation

/// The picked elements as files the agent reads (plan 28 phase E, the owner's choice "C2"): each
/// element's block, its picture by path inside, in `/tmp/cadex-<uid>/<name>.md`, and in the
/// agent's box only `@<path>`, which Claude Code reads by itself (tested 2026-11-17 with a file
/// outside the project). The box keeps one short line, near the mockup's `[button.pay]`.
/// The folder is the user's alone (0700, files 0600); a file older than a day goes on the next pick.
public enum PickFiles {
    /// Short, so the mention stays short in the box (the system's temporary folder is a long path).
    public static var folder: String { "/tmp/cadex-\(getuid())" }
    static let keep: TimeInterval = 24 * 3600

    /// The mention to paste: "@/tmp/cadex-501/button.pay.md " for each element, after writing them.
    /// nil when a file could not be written (the caller pastes the block as before).
    public static func mention(_ delivery: PickDelivery, relativeTo folder: String? = nil, now: Date = Date()) -> String? {
        guard prepare(now: now) else { return nil }
        var used = Set<String>()
        var mentions: [String] = []
        for (index, element) in delivery.elements.enumerated() {
            let block = delivery.noted(index, element.payload(relativeTo: folder, attached: false))
            let path = Self.folder + "/" + unique(name(of: element), used: &used) + ".md"
            guard FileManager.default.createFile(atPath: path, contents: Data(block.utf8), attributes: [.posixPermissions: 0o600]) else { return nil }
            mentions.append("@" + path)
        }
        return mentions.isEmpty ? nil : mentions.joined(separator: " ") + " "
    }

    /// "button.pay" from "main > div.cart button.pay": the selector's last part, in letters,
    /// digits, dots, dashes and underscores only.
    static func name(of element: PickedElement) -> String {
        let last = element.selector.split(whereSeparator: { $0 == " " || $0 == ">" }).last.map(String.init) ?? ""
        let kept = String(last.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) })
        let trimmed = String(kept.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "element" : trimmed
    }

    /// The name, or name-2, name-3… when this pick or a file still there has it.
    static func unique(_ name: String, used: inout Set<String>) -> String {
        var candidate = name, n = 1
        while used.contains(candidate) || FileManager.default.fileExists(atPath: folder + "/" + candidate + ".md") {
            n += 1
            candidate = "\(name)-\(n)"
        }
        used.insert(candidate)
        return candidate
    }

    /// The folder, the user's alone, without files older than a day.
    static func prepare(now: Date) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: folder, isDirectory: &isDir) {
            guard (try? fm.createDirectory(atPath: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else { return false }
        } else {
            // Someone else's folder or a file under that name: not ours to write in.
            guard isDir.boolValue, let owner = (try? fm.attributesOfItem(atPath: folder))?[.ownerAccountID] as? NSNumber,
                  owner.uint32Value == getuid() else { return false }
        }
        for file in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where file.hasSuffix(".md") {
            let path = folder + "/" + file
            if let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date, now.timeIntervalSince(date) > keep {
                try? fm.removeItem(atPath: path)
            }
        }
        return true
    }
}
