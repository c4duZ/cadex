import AppKit
import Customize
import Strings
import UILooks

/// A project's memory settings on a screen (plan 32 D; the owner, 2026-11-18: the .ai-memory.toml
/// "numa tela, ao invés de ficar mexendo nas coisas"), a section of the project's Settings page:
/// where the file lives, its name, what stays out, what each session starts with, and the search and
/// the profile. Each change is written at once to the repository's .ai-memory.toml, only the keys
/// shown (`MemoryMarker`); Cadex makes the file when the project opens (plan 35 B), so what it says
/// is what the hooks do.
@MainActor
public final class MemoryProjectForm: NSView {
    private let folder: String
    private var marker = MemoryMarker()
    private let column = FrameField.column([], gap: DesignTokens.Project.Group.sectionGap)
    private let paths = NSTextView()

    /// `folder`: the project's repository root, where its .ai-memory.toml lives.
    public init(folder: String) {
        self.folder = folder
        super.init(frame: .zero)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        load()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MemoryProjectForm is created in code") }

    public override var isFlipped: Bool { true }

    var file: String { (folder as NSString).appendingPathComponent(MemoryMarker.fileName) }

    private func load() {
        marker = MemoryMarker.read((try? String(contentsOfFile: file, encoding: .utf8)) ?? "")
        show()
    }

    /// Writes the file with the change; a file that does not exist is made only to say something.
    private func change(_ edit: (inout MemoryMarker) -> Void) {
        edit(&marker)
        let old = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        let new = marker.written(over: old)
        guard new != old else { return }
        let text = new.isEmpty || new.hasSuffix("\n") ? new : new + "\n"
        try? text.write(toFile: file, atomically: true, encoding: .utf8)
    }

    /// Four groups in the order they are used (redone 2026-11-19, the owner: too much explaining,
    /// no hierarchy): what a session starts with, search and profile, what is not recorded, and the
    /// file itself last. A row says at most one short line; the options name themselves.
    private func show() {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        typealias R = SettingGroup
        let start = R.section(T("Memory", "Memória"), [
            R.row(T("Briefing at session start", "Briefing ao começar a sessão"),
                  T("The rules and pinned pages, before the first prompt.", "As regras e as páginas fixadas, antes do primeiro pedido."),
                  toggle(marker.briefing) { [weak self] on in self?.change { $0.briefing = on } }),
            R.row(T("Briefing size", "Tamanho do briefing"), T("Characters, about 4 per token.", "Caracteres, uns 4 por token."), stepper()),
            R.row(T("Briefing in subagents", "Briefing nos subagentes"), nil,
                  toggle(marker.subagentBriefing) { [weak self] on in self?.change { $0.subagentBriefing = on } }),
            R.row(T("Hand over the last session", "Passar a última sessão adiante"), nil,
                  toggle(marker.handoff) { [weak self] on in self?.change { $0.handoff = on } }),
            R.row(T("Resume an interrupted session", "Retomar uma sessão interrompida"), nil,
                  toggle(marker.recovery) { [weak self] on in self?.change { $0.recovery = on } }),
        ])
        let search = R.section(T("Search and profile", "Busca e perfil"), [
            R.row(T("Search every project", "Buscar em todos os projetos"), nil,
                  toggle(marker.searchAll) { [weak self] on in self?.change { $0.searchAll = on } }),
            R.row(T("Add to your profile", "Contribuir para o seu perfil"), T("Off for a client's work.", "Desligue para trabalho de cliente."),
                  toggle(marker.contribute) { [weak self] on in self?.change { $0.contribute = on } }),
            R.row(T("Use your profile", "Usar o seu perfil"), nil,
                  toggle(marker.consume) { [weak self] on in self?.change { $0.consume = on } }),
        ])
        let out = R.section(T("Not recorded", "Não gravado"), [
            R.row(T("Subagents' sessions", "Sessões dos subagentes"), nil,
                  toggle(marker.dropSubagents) { [weak self] on in self?.change { $0.dropSubagents = on } }),
            filesRow(),
        ])
        var fileRows: [NSView] = []
        let path = (file as NSString).abbreviatingWithTildeInPath
        if MemoryMarkerPlace.excludeFile(folder: folder) != nil {
            fileRows.append(R.row(T("Where it lives", "Onde fica"), path, place()))
        }
        fileRows += [
            R.row(T("Name in the memory", "Nome na memória"), nil,
                  text(marker.project, T("The repository's folder", "A pasta do repositório")) { [weak self] value in self?.change { $0.project = value } }),
            R.row(T("Workspace", "Espaço"), nil,
                  text(marker.workspace, "default") { [weak self] value in self?.change { $0.workspace = value } }),
        ]
        let fileSection = R.section(T("The file", "O arquivo"), fileRows)
        for view in [start, search, out, fileSection] {
            column.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
    }

    /// The patterns, one per line, under their name: a list wants the row's width.
    private func filesRow() -> NSView {
        let name = FrameField.text(T("Files", "Arquivos"), color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.medium)
        let hint = FrameField.text(T("One pattern per line, like secrets/** or *.env", "Um padrão por linha, como secrets/** ou *.env"),
                                   size: DesignTokens.FontSize.small, color: DesignTokens.Color.textMuted)
        let area = ignored()
        let stack = FrameField.column([name, hint, area], gap: DesignTokens.Project.Group.textGap)
        stack.setCustomSpacing(UILooks.pt(DesignTokens.Project.Group.labelGap), after: hint)
        area.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let row = FrameBox()
        row.hold(stack, padding: DesignTokens.Project.Group.padding)
        return row
    }

    // MARK: Pieces

    private func toggle(_ on: Bool, _ changed: @escaping (Bool) -> Void) -> NSView { SettingGroup.toggle(on, changed) }

    private func text(_ value: String, _ hint: String, _ changed: @escaping (String) -> Void) -> NSView {
        let field = NSTextField(string: value)
        field.placeholderString = hint
        let box = FrameField.field(field)
        box.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Inspector.width) * 3 / 4).isActive = true
        FormTarget.keep(field) { changed(field.stringValue.trimmingCharacters(in: .whitespaces)) }
        return box
    }

    /// In the repository or only on this Mac (the line in the common dir's info/exclude).
    private func place() -> NSView {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: [T("In the repository (commit it)", "No repositório (faça commit)"), T("Only on this Mac (git ignores it)", "Só neste Mac (o git ignora)")])
        popup.selectItem(at: MemoryMarkerPlace.isLocalOnly(folder: folder) ? 1 : 0)
        FormTarget.keep(popup) { [weak self] in
            guard let self else { return }
            MemoryMarkerPlace.setLocalOnly(popup.indexOfSelectedItem == 1, folder: self.folder)
        }
        return FrameField.popup(popup)
    }

    private func stepper() -> NSView {
        let label = FrameField.text("\(marker.briefingChars)", color: DesignTokens.Color.textPrimary)
        label.font = UILooks.monospacedDigits(DesignTokens.FontSize.meta)
        let control = NSStepper()
        control.minValue = Double(MemoryMarker.briefingRange.lowerBound)
        control.maxValue = Double(MemoryMarker.briefingRange.upperBound)
        control.increment = 500
        control.doubleValue = Double(marker.briefingChars)
        FormTarget.keep(control) { [weak self] in
            label.stringValue = "\(Int(control.doubleValue))"
            self?.change { $0.briefingChars = Int(control.doubleValue) }
        }
        let stack = NSStackView(views: [label, control])
        stack.spacing = UILooks.pt(DesignTokens.NewTask.Option.gap)
        return stack
    }

    private func ignored() -> NSView {
        paths.string = marker.ignorePaths.joined(separator: "\n")
        let area = FrameField.area(paths, height: DesignTokens.NewTask.Field.minHeight)
        NotificationCenter.default.addObserver(self, selector: #selector(pathsEdited), name: NSText.didEndEditingNotification, object: paths)
        return area
    }

    /// Written when the editing ends, not at each key: a half-typed pattern is not a rule.
    @objc private func pathsEdited() {
        let list = paths.string.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        change { $0.ignorePaths = list }
    }
}

/// Lets a control call a closure: AppKit sends actions to objects; the target lives with the control.
@MainActor
final class FormTarget: NSObject {
    private let body: () -> Void
    nonisolated(unsafe) private static var key = 0
    private init(_ body: @escaping () -> Void) { self.body = body }

    static func keep(_ control: NSControl, _ body: @escaping () -> Void) {
        let target = FormTarget(body)
        objc_setAssociatedObject(control, &key, target, .OBJC_ASSOCIATION_RETAIN)
        control.target = target
        control.action = #selector(fire)
    }

    @objc private func fire() { body() }
}
