import AppKit
import Strings
import UILooks

/// The unified diff (components.memoryPanel.diff): a monospaced block, the hunk's header on the
/// inset fill, the added lines green, the removed red, each with its sign; "mesmo corpo", "grande
/// demais" and "cortado no limite" as words in its place.
@MainActor
final class PanelDiffView: NSView {
    typealias D = MP.Diff
    let state: PanelDiffState

    init(_ state: PanelDiffState) {
        self.state = state
        super.init(frame: .zero)
        let content: NSView
        switch state {
        case .same: content = PanelScreen.note(T("Same body in both versions.", "Mesmo corpo nas duas versões."))
        case .tooLarge(let why): content = PanelScreen.note(T("Too large to compare: ", "Grande demais para comparar: ") + why)
        case .lines(let lines, let truncated):
            var rows = lines.map(row)
            if truncated { rows.append(PanelScreen.note(T("Cut at the diff's limit.", "Cortado no limite do diff."))) }
            let column = PanelText.column(rows, gap: 0)
            for view in rows { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
            let box = FrameBox()
            box.box(bg: nil, border: D.border, radius: D.radius)
            box.layer?.masksToBounds = true
            box.hold(column, padding: NSEdgeInsets())
            content = box
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(T("Changes", "Alterações"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelDiffView is created in code") }

    /// The sign, the fill and the color of a line.
    static func look(_ line: PanelDiffLine) -> (text: String, bg: NSColor?, color: NSColor) {
        switch line {
        case .hunk(let text): (text, D.Hunk.bg, D.Hunk.color)
        case .same(let text): (" " + text, nil, DesignTokens.Color.textBody)
        case .add(let text): ("+" + text, D.Add.bg, D.Add.color)
        case .del(let text): ("−" + text, D.Del.bg, D.Del.color)
        }
    }

    private func row(_ line: PanelDiffLine) -> NSView {
        let (text, bg, color) = Self.look(line)
        let label = NSTextField(wrappingLabelWithString: text.isEmpty ? " " : text)
        label.font = UILooks.monospaced(D.fontSize)
        label.textColor = color
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let holder = FrameBox()
        holder.box(bg: bg, border: nil, radius: 0)
        if case .hunk = line { holder.hold(label, padding: D.Hunk.padding) } else { holder.hold(label, padding: D.padding) }
        return holder
    }

    /// For tests: each line's words as drawn.
    var linesDrawn: [String] {
        guard case .lines(let lines, _) = state else { return [] }
        return lines.map { Self.look($0).text }
    }
}

/// The history screen (MemoryHistory.dc.html, upstream's history, print 11): the trail to
/// "histórico", the title, the path and the count with ⓘ; the diff of the pair; the versions with
/// De and Para and "Comparar selecionadas".
@MainActor
final class PanelHistoryView: PanelScreen {
    let ref: PanelProjectRef
    let history: PanelHistory
    private(set) var pickFrom: String?
    private(set) var pickTo: String
    private var radios: [(from: NSButton, to: NSButton)] = []
    private let now: Date

    init(_ ref: PanelProjectRef, history: PanelHistory, now: Date = Date(), go: @escaping (PanelPlace) -> Void) {
        (self.ref, self.history, self.now) = (ref, history, now)
        (pickFrom, pickTo) = (history.from, history.to)
        super.init(go: go)
        setAccessibilityLabel(T("History", "Histórico"))
        let path = PanelText.line(history.path, size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        path.font = UILooks.monospaced(MP.Mono.fontSize)
        let count = PanelText.line("· " + PanelWords.versions(history.total), size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        let help = PanelHelpButton(T("Replaced versions stay on record; nothing here can change them.",
                                     "Versões substituídas permanecem no registro; nada aqui pode alterá-las."))
        let sub = PanelText.row([path, count, help, PanelText.spring()], gap: MP.Chip.gap)
        let title = PanelText.line(T("History", "Histórico"), size: MP.Head.Title.fontSize, color: DesignTokens.Color.textPrimary, weight: MP.Head.Title.weight)
        let compare = DesignButton.make(T("Compare selected", "Comparar selecionadas"), .secondary) { [weak self] in self?.compare() }
        let versionsTitle = PanelText.line(versionsRange(), size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary,
                                           weight: DesignTokens.FontWeight.semibold)
        let views: [NSView] = [trail(PanelPlace.history(ref, history.path, from: nil, to: nil).crumbs), title, sub, pairLine(),
                               PanelText.line(history.toTitle, size: DesignTokens.FontSize.meta, color: MP.Head.meta), PanelDiffView(history.diff),
                               versionsTitle, table(), PanelText.row([compare, PanelText.spring()], gap: 0)]
        fill(views)
        for (index, gap) in [(0, MP.Head.titleGap), (1, MP.Head.titleGap), (3, MP.Head.titleGap)] {
            column.setCustomSpacing(UILooks.pt(gap), after: views[index])
        }
    }

    private func versionsRange() -> String {
        let first = history.versions.isEmpty ? 0 : history.offset + 1
        let last = history.offset + history.versions.count
        return T("Versions \(first)–\(last) of \(history.total)", "Versões \(first)–\(last) de \(history.total)")
    }

    /// "Conteúdo de 5ef7d2d8 · nenhuma versão anterior", or "Alterações de X para Y".
    private func pairLine() -> NSView {
        let bold = DesignTokens.FontWeight.semibold
        func mono(_ id: String) -> NSTextField {
            let label = PanelText.line(PanelHistory.short(id), size: MP.Mono.fontSize, color: DesignTokens.Color.textPrimary, weight: bold)
            label.font = UILooks.monospaced(MP.Mono.fontSize, weight: bold)
            return label
        }
        func words(_ text: String, strong: Bool = true) -> NSTextField {
            PanelText.line(text, size: DesignTokens.FontSize.body, color: strong ? DesignTokens.Color.textPrimary : MP.Head.meta, weight: strong ? bold : .regular)
        }
        guard let from = history.from else {
            return PanelText.row([words(T("Content of", "Conteúdo de")), mono(history.to),
                                  words("· " + T("no earlier version", "nenhuma versão anterior"), strong: false), PanelText.spring()], gap: MP.Chip.gap)
        }
        return PanelText.row([words(T("Changes from", "Alterações de")), mono(from), words(T("to", "para")), mono(history.to), PanelText.spring()],
                             gap: MP.Chip.gap)
    }

    private func table() -> NSView {
        let table = PanelTable([PanelColumn(title: T("From", "De"), share: 0.04), PanelColumn(title: T("To", "Para"), share: 0.04),
                                PanelColumn(title: T("Version", "Versão"), share: 0.26), PanelColumn(title: T("Recorded", "Gravação"), share: 0.13),
                                PanelColumn(title: T("Author", "Autor"), share: 0.08), PanelColumn(title: T("Title", "Título"), share: nil),
                                PanelColumn(title: T("Size", "Tamanho"), share: 0.12)])
        typealias R = MP.Table.Row
        radios = []
        table.show(history.versions.map { v in
            let from = radio(v.id == pickFrom, label: T("From ", "De ") + PanelHistory.short(v.id))
            let to = radio(v.id == pickTo, label: T("To ", "Para ") + PanelHistory.short(v.id))
            radios.append((from, to))
            let id = PanelText.line(PanelHistory.short(v.id), size: R.fontSize, color: DesignTokens.Color.textPrimary)
            id.font = UILooks.monospaced(R.fontSize)
            id.setContentCompressionResistancePriority(.required, for: .horizontal)
            var version: [NSView] = [id]
            if v.isLatest { version.append(PanelChip.make(T("latest", "mais recente"), .green)) }
            if let previous = v.supersedes {
                version.append(PanelText.line(T("replaced ", "substituiu ") + PanelHistory.short(previous), size: DesignTokens.FontSize.meta, color: MP.Head.meta))
            }
            return [from, to, PanelText.row(version + [PanelText.spring()], gap: MP.Chip.gap),
                    PanelText.line(v.created.map { PanelWords.ago($0, now: now) } ?? "—", size: R.fontSize, color: R.color),
                    PanelText.line("—", size: R.fontSize, color: R.color), PanelText.line(v.title, size: R.fontSize, color: R.color),
                    PanelText.line(PanelWords.chars(v.chars), size: R.fontSize, color: R.color)]
        })
        return table
    }

    private func radio(_ on: Bool, label: String) -> NSButton {
        let button = NSButton(radioButtonWithTitle: "", target: self, action: #selector(picked(_:)))
        button.state = on ? .on : .off
        button.setAccessibilityLabel(label)
        return button
    }

    @objc private func picked(_ sender: NSButton) {
        for (index, pair) in radios.enumerated() {
            let id = history.versions[index].id
            if pair.from === sender { pickFrom = id }
            if pair.to === sender { pickTo = id }
        }
        for (index, pair) in radios.enumerated() {
            pair.from.state = history.versions[index].id == pickFrom ? .on : .off
            pair.to.state = history.versions[index].id == pickTo ? .on : .off
        }
    }

    /// "Comparar selecionadas": the history again with the pair chosen.
    func compare() { go(.history(ref, history.path, from: pickFrom, to: pickTo)) }

    /// For tests.
    func pick(from: Int?, to: Int) {
        if let from { picked(radios[from].from) }
        picked(radios[to].to)
    }
}
