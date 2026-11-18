import CCadex

/// Claude Code's screen in the theme's colors and the pane's shapes (plan 33; the colors and
/// shapes measured on Claude Code 2.1.327 are in docs/spec/terminal.md, "As cores e as formas do
/// Claude Code"). Pure: it reads the frame's cells and returns what the drawing changes. Only
/// while Claude runs in front (it reports itself by OSC 7501); what it does not recognize stays as
/// Claude drew it, so a new Claude version can only bring back Claude's own look.
struct ClaudeDress {
    /// The theme's colors for Claude's fixed ones, worked out from the terminal's own colors so
    /// every theme gets them (0xRRGGBB).
    struct Palette: Equatable {
        var userBackground, strong, dim, separator: UInt32
        var addBackground, addText, addSign, deleteBackground, deleteText, deleteSign: UInt32
        var toolDone, toolRunning, live, accent, modeEdits, modePlan, boxLine: UInt32

        init(_ a: TerminalAppearance) {
            let bg = a.background, fg = a.foreground
            func ansi(_ i: Int) -> UInt32 { i < a.ansi.count ? a.ansi[i] : fg }
            // The mixes give the mockup's tokens on Cadex Night (bg.userMessage, diff.*, text.tertiary,
            // line.control), measured against tokens.json on 2026-11-18.
            userBackground = mix(bg, fg, 0.07)
            strong = ansi(15)
            dim = mix(fg, bg, 0.42)
            separator = ansi(8)
            addBackground = mix(bg, ansi(2), 0.13)
            addText = mix(fg, ansi(2), 0.35)
            addSign = ansi(10)
            deleteBackground = mix(bg, ansi(1), 0.13)
            deleteText = mix(fg, ansi(1), 0.35)
            deleteSign = ansi(9)
            toolDone = ansi(2)
            toolRunning = ansi(3)
            live = ansi(12)
            accent = ansi(14)
            modeEdits = ansi(13)
            modePlan = ansi(6)
            boxLine = mix(bg, fg, 0.13)
        }
    }

    /// A rounded rectangle in cell coordinates: rows and columns it covers, filled or outlined.
    struct Shape: Equatable {
        var top: Int, bottom: Int, left: Int, right: Int
        var color: UInt32
        var outline: Bool
        /// From the middle of the first row to the middle of the last (the input box sits on its rules).
        var midRows: Bool
    }

    /// The changes for one frame: the cells with new colors, the cells not drawn, the shapes under
    /// the text, and the mode's words on the status line's row.
    struct Plan {
        var cells: [cadex_terminal_cell]
        var hidden: [Bool]
        var shapes: [Shape] = []
        var label: (text: String, row: Int, color: UInt32)?
    }

    /// `atBottom`: the view shows the screen, not the history above it (the mode line is the
    /// screen's last row only then).
    static func plan(cells source: UnsafePointer<cadex_terminal_cell>, text: UnsafePointer<UInt8>,
                     cols: Int, rows: Int, palette p: Palette, atBottom: Bool = true) -> Plan {
        let count = cols * rows
        var plan = Plan(cells: Array(UnsafeBufferPointer(start: source, count: count)), hidden: Array(repeating: false, count: count))
        // The text from the frame's own cells: the plan's change while they are read.
        func string(_ i: Int) -> String {
            let c = source[i]
            return String(decoding: UnsafeBufferPointer(start: text + Int(c.text_offset), count: Int(c.text_len)), as: UTF8.self)
        }
        func row(_ r: Int) -> String { (0..<cols).map { string(r * cols + $0) }.map { $0.isEmpty ? " " : $0 }.joined() }
        let lines = (0..<rows).map(row)
        hideMascot(&plan, lines: lines, cols: cols)
        box(&plan, lines: lines, cols: cols, palette: p)
        userMessage(&plan, cols: cols, rows: rows, palette: p)
        if atBottom { modeLine(&plan, lines: lines, cols: cols, palette: p) }
        recolor(&plan, string: string, palette: p)
        return plan
    }
}

extension ClaudeDress {
    /// The mascot: block elements in Claude's orange at the start of a banner row ("▐▛███▜▌").
    static func hideMascot(_ plan: inout Plan, lines: [String], cols: Int) {
        for (r, line) in lines.enumerated() {
            let head = Array(line.prefix(10))
            guard head.filter(isBlock).count >= 2, head.allSatisfy({ $0 == " " || isBlock($0) }) else { continue }
            for c in 0..<min(10, cols) where plan.cells[r * cols + c].fg == Mascot.color || head[c] == " " {
                plan.hidden[r * cols + c] = true
            }
        }
    }

    /// A character of the Unicode block "Block Elements" (U+2580 to U+259F), the mascot's.
    static func isBlock(_ c: Character) -> Bool {
        c.unicodeScalars.count == 1 && (0x2580...0x259F).contains(c.unicodeScalars.first!.value)
    }

    /// The input: two whole rows of "─" in the rules' color around rows starting with "❯".
    static func box(_ plan: inout Plan, lines: [String], cols: Int, palette p: Palette) {
        func isRule(_ r: Int) -> Bool {
            lines[r].allSatisfy { $0 == "─" } && Rules.colors.contains(plan.cells[r * cols].fg)
        }
        var r = 0
        while r < lines.count {
            guard isRule(r), let end = (r + 2..<min(lines.count, r + 12)).first(where: isRule),
                  lines[r + 1].hasPrefix("❯") else { r += 1; continue }
            for row in [r, end] { for c in 0..<cols { plan.hidden[row * cols + c] = true } }
            plan.shapes.append(Shape(top: r, bottom: end, left: 0, right: cols - 1, color: p.boxLine, outline: true, midRows: true))
            r = end + 1
        }
    }

    /// The owner's message: its background drawn as one rounded block instead of cell by cell.
    static func userMessage(_ plan: inout Plan, cols: Int, rows: Int, palette p: Palette) {
        var r = 0
        while r < rows {
            guard Background.user.contains(plan.cells[r * cols].bg), hasBackground(plan.cells[r * cols]) else { r += 1; continue }
            var end = r
            while end + 1 < rows, Background.user.contains(plan.cells[(end + 1) * cols].bg) { end += 1 }
            for i in (r * cols)..<((end + 1) * cols) where Background.user.contains(plan.cells[i].bg) {
                plan.cells[i].flags &= ~UInt16(CADEX_CELL_HAS_BACKGROUND)
            }
            plan.shapes.append(Shape(top: r, bottom: end, left: 0, right: cols - 1, color: p.userBackground, outline: false, midRows: false))
            r = end + 1
        }
    }

    /// The mode line ("⏵⏵ accept edits on (shift+tab to cycle)") read, not drawn, and its words put
    /// at the right of the row above (the status line), when that end is free.
    static func modeLine(_ plan: inout Plan, lines: [String], cols: Int, palette p: Palette) {
        guard let r = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }), r > 0 else { return }
        let line = lines[r].trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("⏵⏵ ") || line.hasPrefix("⏸ "), let on = line.range(of: " on") else { return }
        let words = String(line[line.index(line.startIndex, offsetBy: 2)..<on.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty, words.count < 30 else { return }
        let first = Array(lines[r]).firstIndex(where: { $0 != " " }) ?? 0
        let color = plan.cells[r * cols + min(first, cols - 1)].fg
        for c in 0..<cols { plan.hidden[r * cols + c] = true }
        let above = Array(lines[r - 1])
        guard above.suffix(words.count + 2).allSatisfy({ $0 == " " }) else { return }
        plan.label = (words, r - 1, Fixed.mode[color].map { $0 == .plan ? p.modePlan : p.modeEdits } ?? p.modeEdits)
    }

    /// Claude's fixed colors to the theme's (the table in the spec), the text color by its background.
    static func recolor(_ plan: inout Plan, string: (Int) -> String, palette p: Palette) {
        for i in plan.cells.indices {
            var cell = plan.cells[i]
            let bg = hasBackground(cell) ? cell.bg : nil
            switch bg {
            case let b? where Background.delete.contains(b): cell.bg = p.deleteBackground
            case let b? where Background.add.contains(b): cell.bg = p.addBackground
            default: break
            }
            cell.fg = Fixed.color(cell.fg, background: bg, text: string(i), palette: p) ?? cell.fg
            plan.cells[i] = cell
        }
    }

    static func hasBackground(_ c: cadex_terminal_cell) -> Bool { c.flags & UInt16(CADEX_CELL_HAS_BACKGROUND) != 0 }
}

/// The measured colors (docs/spec/terminal.md), "dark" and "light" together: they do not collide.
enum Mascot { static let color: UInt32 = 0xD77757 }
enum Rules { static let colors: Set<UInt32> = [0x888888, 0x8A8A8A] }
enum Background {
    static let user: Set<UInt32> = [0x373737, 0xF0F0F0]
    static let delete: Set<UInt32> = [0x3D0100, 0xFFDCDC]
    static let add: Set<UInt32> = [0x022800, 0xDCFFDC]
}

enum Fixed {
    enum Mode { case edits, plan }
    static let mode: [UInt32: Mode] = [0xAF87FF: .edits, 0x8700FF: .edits, 0x48968C: .plan]

    static func color(_ fg: UInt32, background bg: UInt32?, text: String, palette p: ClaudeDress.Palette) -> UInt32? {
        if let bg, Background.delete.contains(bg) { return [0xDC5A5A, 0xCF222E].contains(fg) ? p.deleteSign : p.deleteText }
        if let bg, Background.add.contains(bg) { return [0x50C850, 0x248A3D].contains(fg) ? p.addSign : p.addText }
        switch fg {
        case 0xFFFFFF: return p.strong
        case 0x000000 where bg.map({ Background.user.contains($0) }) ?? false: return p.strong
        case 0x999999, 0x666666: return text == "⏺" ? p.toolRunning : p.dim
        case 0x505050, 0xAFAFAF: return p.separator
        case Mascot.color: return p.live
        case 0x4EBA65, 0x2C7A39: return p.toolDone
        case 0xB1B9F9, 0x5769F7: return p.accent
        case 0xAF87FF, 0x8700FF: return p.modeEdits
        case 0x48968C: return p.modePlan
        default: return nil
        }
    }
}

/// `a` moved toward `b` by `t` (0…1), per channel.
func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
    func part(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) + (ch(b, s) - ch(a, s)) * t).rounded()) << s }
    return part(16) | part(8) | part(0)
}
