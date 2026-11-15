import Foundation

/// The front window of an app as the agent reads it (docs/spec/computer-use.md):
/// role, title, value and state per line, indented, each element with an
/// index (`#3`) valid until the next read of that app; at most 400
/// elements and 200 characters a text; a password field shows no value.
@MainActor
struct ComputerUseTree {
    static let maxElements = 400
    static let maxText = 200

    let text: String
    /// Index → element, for the actions until the next read.
    let elements: [Int: any ComputerUseNode]
    /// How many were left out past the limit.
    let left: Int

    /// Roles that are only structure: their children come up a level.
    static let structure: Set<String> = ["AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXUnknown"]

    init(window: any ComputerUseNode) {
        var lines: [String] = []
        var elements: [Int: any ComputerUseNode] = [:]
        var left = 0
        Self.walk(window, 0, &lines, &elements, &left)
        self.text = lines.joined(separator: "\n") + (left > 0 ? "\n… \(left) more elements left out" : "")
        self.elements = elements
        self.left = left
    }

    /// A method, not a nested function: the release build saw the nested
    /// one's captures as a data race (make perf, 2026-11-15).
    private static func walk(_ node: any ComputerUseNode, _ depth: Int, _ lines: inout [String],
                             _ elements: inout [Int: any ComputerUseNode], _ left: inout Int) {
        let quiet = structure.contains(node.role) && node.title.isEmpty
        var deeper = depth
        if !quiet {
            if elements.count >= maxElements { left += 1; return }
            let index = elements.count + 1
            elements[index] = node
            lines.append(String(repeating: "  ", count: depth) + line(node, index: index))
            deeper = depth + 1
        }
        for child in node.children { walk(child, deeper, &lines, &elements, &left) }
    }

    static func line(_ node: any ComputerUseNode, index: Int) -> String {
        var line = "- " + node.role.replacingOccurrences(of: "AX", with: "").lowercased()
        let title = clip(node.title)
        if !title.isEmpty { line += " " + quoted(title) }
        if node.isSecure {
            line += " [password]"
        } else if let value = node.value, !value.isEmpty, value != node.title {
            line += " value=" + quoted(clip(value))
        }
        var state: [String] = []
        if !node.isEnabled { state.append("disabled") }
        if node.isFocused { state.append("focused") }
        if !state.isEmpty { line += " [" + state.joined(separator: ", ") + "]" }
        return line + " [#\(index)]"
    }

    static func clip(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > maxText ? String(flat.prefix(maxText - 1)) + "…" : flat
    }

    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
