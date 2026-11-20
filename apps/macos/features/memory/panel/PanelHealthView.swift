import AppKit
import Strings
import UILooks

/// Saúde do servidor (MemoryHealth.dc.html, upstream's health page, print 07), this Mac's
/// cadex-memory as the server: VERIFICAÇÕES (all passing in green, or each failing one, error or
/// warning, with its fix as a button that runs memory.fix-health, where upstream prints a command to
/// type), then upstream's five sections in two columns, a name and its value in mono on each line.
/// A fix done reads the page again and says what it did over the checks.
@MainActor
final class PanelHealthView: PanelScreen, PanelWriting {
    let health: PanelHealth
    private let write: (PanelWrite) -> Void
    private let reload: (String?) -> Void
    private(set) var fixButtons: [String: NSButton] = [:]
    private let status = PanelScreen.note("")

    /// `said`: what the last fix did, kept across the read again.
    init(_ health: PanelHealth, said: String? = nil, write: @escaping (PanelWrite) -> Void, reload: @escaping (String?) -> Void,
         go: @escaping (PanelPlace) -> Void) {
        (self.health, self.write, self.reload) = (health, write, reload)
        super.init(go: go)
        setAccessibilityLabel(T("Server health", "Saúde do servidor"))
        let head = heading(T("Server health", "Saúde do servidor"))
        let note = PanelScreen.note(T("The cadex-memory process of this Mac", "O processo cadex-memory deste Mac"))
        note.toolTip = T("Counters, queues and model state of this engine; a fix runs from its button.",
                         "Contadores, filas e estado dos modelos deste engine; cada correção roda pelo botão dela.")
        status.stringValue = said ?? ""
        status.textColor = MP.Ok.color
        status.isHidden = said == nil
        fill([head, note, status, PanelScreen.label(T("Checks", "Verificações")), checks(), sections()])
        column.setCustomSpacing(UILooks.pt(MP.Empty.gap), after: head)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelHealthView is created in code") }

    private func checks() -> NSView {
        guard !health.checks.isEmpty else {
            return PanelText.row([dot(MP.Ok.dot), PanelText.line(T("Every server-side check passes.", "Todas as verificações do servidor passaram."),
                                                                 size: DesignTokens.FontSize.panel, color: MP.Ok.color), PanelText.spring()], gap: MP.Chip.gap)
        }
        let boxes = health.checks.map { check -> NSView in
            let color = check.error ? MP.Inbox.error : MP.Notice.title
            let word = PanelText.line((check.error ? T("error", "erro") : T("warn", "aviso")).uppercased(), size: MP.Label.fontSize, color: color,
                                      weight: MP.Label.weight)
            word.font = UILooks.monospaced(MP.Label.fontSize)
            let words = PanelScreen.note(check.words, color: DesignTokens.Color.textBody)
            var lines: [NSView] = [PanelText.row([word, words], gap: MP.Chip.gap)]
            if let fix = check.fix {
                let button = DesignButton.make(PanelHealth.fixTitle(fix), .secondary) { [weak self] in self?.run(fix) }
                fixButtons[fix] = button
                lines.append(PanelText.row([PanelText.line(T("Fix:", "Correção:"), size: DesignTokens.FontSize.meta, color: MP.Head.meta), button,
                                            PanelText.spring()], gap: MP.Chip.gap))
            } else if let note = check.note {
                lines.append(PanelScreen.note(T("Fix: ", "Correção: ") + note))
            }
            let column = PanelText.column(lines, gap: MP.Inbox.fieldGap)
            let box = PanelScreen.box(column)
            box.setAccessibilityElement(true)
            box.setAccessibilityRole(.group)
            box.setAccessibilityLabel((check.error ? T("Error: ", "Erro: ") : T("Warning: ", "Aviso: ")) + check.words)
            return box
        }
        let stack = PanelText.column(boxes, gap: MP.Inbox.detailGap)
        for box in boxes { box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private func dot(_ color: NSColor) -> NSView {
        let spot = FrameBox()
        spot.box(bg: color, border: nil, radius: MP.Chip.dot / 2)
        spot.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Chip.dot)).isActive = true
        spot.heightAnchor.constraint(equalToConstant: UILooks.pt(MP.Chip.dot)).isActive = true
        return spot
    }

    /// Hooks, writer and consolidation at the left; models and index at the right (the board).
    private func sections() -> NSView {
        let boxes = health.sections.map(section)
        let left = PanelText.column(Array(boxes.prefix(3)), gap: MP.Page.gap)
        let right = PanelText.column(Array(boxes.dropFirst(3)), gap: MP.Page.gap)
        for (box, side) in boxes.enumerated().map({ ($0.element, $0.offset < 3 ? left : right) }) {
            box.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true
        }
        let row = NSStackView(views: [left, right])
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = UILooks.pt(MP.Page.gap)
        return row
    }

    private func section(_ s: PanelHealth.Section) -> NSView {
        var lines: [NSView] = [PanelScreen.label(s.title)]
        for (index, r) in s.rows.enumerated() {
            if index > 0 { lines.append(PanelScreen.rule()) }
            let name = PanelText.line(r.name, size: DesignTokens.FontSize.panel, color: MP.Box.Row.name)
            name.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Box.Row.nameWidth) * 0.8).isActive = true
            let value = NSTextField(wrappingLabelWithString: r.value)
            value.font = UILooks.monospaced(MP.Mono.fontSize)
            value.textColor = MP.Box.Row.value
            value.isSelectable = true
            value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let line = PanelText.row([name, value], gap: MP.Box.Row.gap)
            line.alignment = .firstBaseline
            line.setAccessibilityElement(true)
            line.setAccessibilityLabel(r.name + ": " + r.value)
            lines.append(line)
        }
        let column = PanelText.column(lines, gap: MP.Inbox.fieldGap)
        for view in lines.dropFirst() { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        return PanelScreen.box(column)
    }

    private func run(_ fix: String) {
        fixButtons[fix]?.isEnabled = false
        write(.fix(fix))
    }

    func finished(_ done: PanelWrite, _ answer: Result<Data, PanelReadError>) {
        guard case .fix(let what) = done else { return }
        switch answer {
        case .success(let data):
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let n = { (key: String) in PanelOverviewData.int(o[key]) }
            let said: String = switch what {
            case "spool": T("\(n("delivered")) event(s) sent; \(n("pending")) still queued.", "\(n("delivered")) evento(s) enviados; \(n("pending")) ainda na fila.")
            case "compact": T("\(n("bytes_reclaimed")) bytes reclaimed.", "\(n("bytes_reclaimed")) bytes recuperados.")
            default: T("\(n("embedded")) vector(s) made, \(n("skipped")) skipped, \(n("failed")) failed.",
                       "\(n("embedded")) vetor(es) gerados, \(n("skipped")) pulados, \(n("failed")) com falha.")
            }
            reload(said)
        case .failure(let e):
            fixButtons[what]?.isEnabled = true
            status.textColor = MP.Inbox.error
            status.stringValue = e.words
            status.isHidden = false
        }
    }

    /// The owner said no (compact): its button back.
    func cancelled(_ what: String) { fixButtons[what]?.isEnabled = true }

    /// For tests.
    var statusSaid: String { status.isHidden ? "" : status.stringValue }
}
