import AppKit

/// A reply's Markdown, as a terminal shows it: **bold**, *italic*, `code`
/// and links styled, headings bold, list dashes as bullets and code fences
/// dropped with their lines kept. Foundation parses the inline part; the
/// lines are read here, which is all a reply in the tab needs.
@MainActor
enum AgentMarkdown {
    static func render(_ text: String, font: NSFont, bold: NSFont, colors: AgentColors) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var inFence = false
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if index > 0 && out.length > 0 { out.append(NSAttributedString(string: "\n")) }
            if inFence {
                out.append(NSAttributedString(string: raw, attributes: [.font: font, .foregroundColor: colors.accent]))
                continue
            }
            var line = raw
            var lineFont = font
            if let heading = line.range(of: #"^#{1,6} "#, options: .regularExpression) {
                line.removeSubrange(heading)
                lineFont = bold
            } else if let bullet = line.range(of: #"^(\s*)[-*] "#, options: .regularExpression) {
                let spaces = line[bullet].prefix { $0 == " " }
                line.replaceSubrange(bullet, with: spaces + "• ")
            }
            out.append(inline(line, font: lineFont, bold: bold, colors: colors))
        }
        return out
    }

    /// One line's inline Markdown; as plain text if it does not parse.
    static func inline(_ line: String, font: NSFont, bold: NSFont, colors: AgentColors) -> NSAttributedString {
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colors.text]
        guard line.contains(where: { "*_`[".contains($0) }),
              let parsed = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: line, attributes: plain)
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes = plain
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { attributes[.font] = bold }
            if intent.contains(.emphasized) { attributes[.obliqueness] = 0.15 }
            if intent.contains(.code) { attributes[.foregroundColor] = colors.accent }
            if run.link != nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return out
    }
}
