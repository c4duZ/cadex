import AppKit
import UILooks

/// How each entry of a subagent's conversation is written, after the way
/// Claude Code writes it in the terminal (the owner asked for that look,
/// 2026-10-21): "● Bash(make test)" with "⎿" and the first lines of what it
/// gave back under it, edits as red and green lines, replies in Markdown,
/// your messages after "> ". All in the monospaced font, as in a terminal.
@MainActor
struct AgentTranscriptStyle {
    let colors: AgentColors
    var font: NSFont { .monospacedSystemFont(ofSize: UILooks.pt(12), weight: .regular) }
    var bold: NSFont { .monospacedSystemFont(ofSize: UILooks.pt(12), weight: .semibold) }
    static let done = NSColor.systemGreen
    static let failed = NSColor.systemRed

    func entry(_ entry: AgentTranscriptEntry) -> NSAttributedString {
        switch entry {
        case .prompt(let text): prompt(text)
        case .reply(let text): reply(text)
        case .tool(let name, let subject, let diff): tool(name, subject, diff)
        case .result(let lines, let more, let failed): result(lines, more: more, failed: failed)
        }
    }

    func heading(_ title: String, _ detail: String) -> NSAttributedString {
        let out = NSMutableAttributedString(string: title + "\n", attributes: [.font: UILooks.font(15, weight: .semibold),
                                                                               .foregroundColor: colors.text, .paragraphStyle: paragraph(after: 2)])
        out.append(NSAttributedString(string: detail + "\n", attributes: [.font: UILooks.font(11), .foregroundColor: colors.secondary,
                                                                          .paragraphStyle: paragraph(after: 14)]))
        return out
    }

    /// "> Find the bug": the task, or a later message, on a soft ground.
    private func prompt(_ text: String) -> NSAttributedString {
        let out = NSMutableAttributedString(string: "> ", attributes: [.font: bold, .foregroundColor: colors.secondary])
        out.append(NSAttributedString(string: Self.tight(text), attributes: [.font: font, .foregroundColor: colors.text]))
        out.append(NSAttributedString(string: "\n"))
        out.addAttribute(.backgroundColor, value: colors.fill.withAlphaComponent(0.55), range: NSRange(location: 0, length: out.length))
        block(out, indent: "> ", after: 12)
        return out
    }

    /// "● " and the reply in Markdown, its lines under the first.
    private func reply(_ text: String) -> NSAttributedString {
        let out = NSMutableAttributedString(string: "● ", attributes: [.font: font, .foregroundColor: colors.text])
        out.append(AgentMarkdown.render(Self.tight(text), font: font, bold: bold, colors: colors))
        out.append(NSAttributedString(string: "\n"))
        block(out, indent: "● ", after: 12)
        return out
    }

    /// "● Edit(App.swift)" and, for an edit, its lines out and in.
    private func tool(_ name: String, _ subject: String, _ diff: [AgentDiffLine]) -> NSAttributedString {
        let out = NSMutableAttributedString(string: "● ", attributes: [.font: font, .foregroundColor: Self.done])
        out.append(NSAttributedString(string: name, attributes: [.font: bold, .foregroundColor: colors.text]))
        if !subject.isEmpty {
            out.append(NSAttributedString(string: "(" + subject + ")", attributes: [.font: font, .foregroundColor: colors.secondary]))
        }
        out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph(after: diff.isEmpty ? 2 : 0, indent: "● ")]))
        out.addAttribute(.paragraphStyle, value: paragraph(after: diff.isEmpty ? 2 : 0, indent: "● "), range: NSRange(location: 0, length: out.length))
        for (index, line) in diff.enumerated() {
            let color = line.added ? Self.done : Self.failed
            let row = NSMutableAttributedString(string: index == 0 ? Self.hook : "", attributes: [.font: font, .foregroundColor: colors.secondary])
            row.append(NSAttributedString(string: (line.added ? "+ " : "- ") + line.text + "\n", attributes: [
                .font: font, .foregroundColor: color, .backgroundColor: color.withAlphaComponent(0.14)]))
            row.addAttribute(.paragraphStyle, value: hooked(first: index == 0, after: index == diff.count - 1 ? 2 : 0, truncates: true),
                             range: NSRange(location: 0, length: row.length))
            out.append(row)
        }
        return out
    }

    /// "  ⎿  first line", two more, then "… +40 lines".
    private func result(_ lines: [String], more: Int, failed: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var rows = lines
        if more > 0 { rows.append("… +\(more) " + (more == 1 ? "line" : "lines")) }
        if rows.isEmpty { rows = ["(no output)"] }
        for (index, text) in rows.enumerated() {
            let quiet = more > 0 && index == rows.count - 1
            let row = NSMutableAttributedString(string: index == 0 ? Self.hook : "", attributes: [.font: font, .foregroundColor: colors.secondary])
            row.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font, .foregroundColor: failed ? Self.failed : quiet ? colors.secondary.withAlphaComponent(0.7) : colors.secondary]))
            row.addAttribute(.paragraphStyle, value: hooked(first: index == 0, after: index == rows.count - 1 ? 12 : 0, truncates: true),
                             range: NSRange(location: 0, length: row.length))
            out.append(row)
        }
        return out
    }

    /// The "  ⎿  " that starts what a tool gave back. The lines under it
    /// start where its text does, measured: "⎿" is not as wide as a space
    /// in the font, and five spaces left them out of line.
    static let hook = "  ⎿  "

    private func hooked(first: Bool, after: CGFloat, truncates: Bool) -> NSParagraphStyle {
        let style = paragraph(after: after, indent: Self.hook, truncates: truncates).mutableCopy() as! NSMutableParagraphStyle
        if !first { style.firstLineHeadIndent = style.headIndent }
        return style
    }

    /// A block of several paragraphs written as one: every line after the
    /// first starts under the text, past `indent`, and the space comes once
    /// at its end (each paragraph had it, which opened gaps in a long task).
    private func block(_ out: NSMutableAttributedString, indent: String, after: CGFloat) {
        let string = out.string as NSString
        var location = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let style = paragraph(after: NSMaxRange(range) >= string.length ? after : 0, indent: indent).mutableCopy() as! NSMutableParagraphStyle
            if location > 0 { style.firstLineHeadIndent = style.headIndent }
            out.addAttribute(.paragraphStyle, value: style, range: range)
            location = NSMaxRange(range)
        }
    }

    /// No more than one empty line in a row.
    static func tight(_ text: String) -> String {
        text.replacingOccurrences(of: #"\n\s*\n(\s*\n)+"#, with: "\n\n", options: .regularExpression)
    }

    /// Lines after the first start under the text, past `indent`.
    private func paragraph(after: CGFloat, indent: String = "", truncates: Bool = false) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = after
        style.lineSpacing = 2
        style.headIndent = (indent as NSString).size(withAttributes: [.font: font]).width
        if truncates { style.lineBreakMode = .byTruncatingTail }
        return style
    }
}
