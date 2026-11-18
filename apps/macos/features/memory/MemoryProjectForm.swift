import AppKit
import Customize
import Strings
import UILooks

/// A project's memory settings on a screen (plan 32 D; the owner, 2026-11-18: the .ai-memory.toml
/// "numa tela, ao invés de ficar mexendo nas coisas"), a section of the project's Settings page:
/// its name, what stays out, what each session starts with, and the search and the profile. Each change is written at
/// once to the repository's .ai-memory.toml, only the keys shown (`MemoryMarker`); no file is made
/// while everything is the default.
@MainActor
public final class MemoryProjectForm: NSView {
    private let folder: String
    private var marker = MemoryMarker()
    private let column = FrameField.column([], gap: DesignTokens.Project.Columns.listGap)
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

    private func show() {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let where_ = FrameField.wrapping(T("Saved in ", "Gravado em ") + (file as NSString).abbreviatingWithTildeInPath
                                             + T(", the repository's own file: commit it to share it with the team.", ", o arquivo do próprio repositório: faça commit para valer para o time."))
        var rows: [NSView] = [FrameField.label(T("Memory", "Memória")), where_]
        rows += [FrameField.label(T("Name", "Nome")),
                 row(T("Project name", "Nome do projeto"), T("Empty: the repository's folder.", "Vazio: a pasta do repositório."),
                     text(marker.project, T("From the repository", "Do repositório")) { [weak self] value in self?.change { $0.project = value } }),
                 row(T("Workspace", "Espaço"), T("Projects in the same workspace can be searched together. Empty: the default one.",
                                                   "Projetos no mesmo espaço podem ser buscados juntos. Vazio: o padrão."),
                     text(marker.workspace, "default") { [weak self] value in self?.change { $0.workspace = value } }),
                 FrameField.label(T("What stays out", "O que fica de fora")),
                 FrameField.labeled(T("Files not recorded, one pattern per line", "Arquivos que não são gravados, um padrão por linha"), ignored()),
                 row(T("Don't keep subagents' sessions", "Não guardar as sessões dos subagentes"),
                     T("For runs that fan one task out to many subagents.", "Para execuções que espalham uma tarefa em muitos subagentes."),
                     toggle(marker.dropSubagents) { [weak self] on in self?.change { $0.dropSubagents = on } }),
                 FrameField.label(T("When a session starts", "Quando uma sessão começa")),
                 row(T("The project's briefing", "O briefing do projeto"),
                     T("The rules, pinned pages and what changed lately, before the first prompt.", "As regras, as páginas fixadas e o que mudou por último, antes do primeiro pedido."),
                     toggle(marker.briefing) { [weak self] on in self?.change { $0.briefing = on } }),
                 row(T("Briefing size", "Tamanho do briefing"), T("In characters, about 4 per token.", "Em caracteres, uns 4 por token."), stepper()),
                 row(T("Briefing in subagents too", "Briefing nos subagentes também"), T("Each subagent pays for it in tokens.", "Cada subagente paga em tokens."),
                     toggle(marker.subagentBriefing) { [weak self] on in self?.change { $0.subagentBriefing = on } }),
                 row(T("Hand over the last session", "Passar a última sessão adiante"),
                     T("What the session before left half done.", "O que a sessão anterior deixou pela metade."),
                     toggle(marker.handoff) { [weak self] on in self?.change { $0.handoff = on } }),
                 row(T("Resume an interrupted session", "Retomar uma sessão interrompida"),
                     T("A session that ended without its end (a closed tab, a quota).", "Uma sessão que acabou sem fim (aba fechada, cota)."),
                     toggle(marker.recovery) { [weak self] on in self?.change { $0.recovery = on } }),
                 FrameField.label(T("Search and profile", "Busca e perfil")),
                 row(T("Search every project", "Buscar em todos os projetos"), T("For a repository that needs its siblings' context.", "Para um repositório que precisa do contexto dos irmãos."),
                     toggle(marker.searchAll) { [weak self] on in self?.change { $0.searchAll = on } }),
                 row(T("Add to your profile", "Contribuir para o seu perfil"),
                     T("Your usual choices learned here help other projects. Off for a client's work.", "As suas escolhas de sempre aprendidas aqui ajudam outros projetos. Desligue para trabalho de cliente."),
                     toggle(marker.contribute) { [weak self] on in self?.change { $0.contribute = on } }),
                 row(T("Use your profile", "Usar o seu perfil"), T("Sessions here start with your usual choices.", "As sessões aqui começam com as suas escolhas de sempre."),
                     toggle(marker.consume) { [weak self] on in self?.change { $0.consume = on } })]
        for view in rows {
            column.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
    }

    // MARK: Pieces (the settings window's rows: the project page's row, label left, control right)

    private func row(_ title: String, _ detail: String?, _ control: NSView) -> NSView {
        var words: [NSView] = [FrameField.text(title, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)]
        if let detail { words.append(FrameField.wrapping(detail)) }
        let left = FrameField.column(words, gap: DesignTokens.Project.Row.textGap)
        left.translatesAutoresizingMaskIntoConstraints = true
        // A stack view's own hug: the words take the row, the control goes right (as the
        // settings' rows; the switches sat beside the words, 2026-11-18).
        left.setHuggingPriority(.init(1), for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        let line = NSStackView(views: [left, control])
        line.distribution = .fill
        line.spacing = UILooks.pt(DesignTokens.Project.Row.gap)
        line.alignment = .centerY
        let box = FrameBox()
        box.box(bg: DesignTokens.Project.Row.bg, border: DesignTokens.Project.Row.border, radius: DesignTokens.Project.Row.radius)
        box.hold(line, padding: DesignTokens.Project.Stat.padding)
        return box
    }

    private func toggle(_ on: Bool, _ changed: @escaping (Bool) -> Void) -> NSView {
        let control = ThemeSwitch(on: on, accent: DesignTokens.Project.Toggle.on, off: DesignTokens.Project.Toggle.off, label: "")
        control.onChange = changed
        return control
    }

    private func text(_ value: String, _ hint: String, _ changed: @escaping (String) -> Void) -> NSView {
        let field = NSTextField(string: value)
        field.placeholderString = hint
        let box = FrameField.field(field)
        box.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Inspector.width) * 3 / 4).isActive = true
        FormTarget.keep(field) { changed(field.stringValue.trimmingCharacters(in: .whitespaces)) }
        return box
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
