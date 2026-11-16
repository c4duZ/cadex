import AppKit
import Strings

/// "New Race"'s form (docs/spec/orchestration.md, "Corrida"): the name, the
/// prompt, the starting branch and one row per contender (account, model,
/// machine). The app shows it in a sheet with the caps it will use, and
/// reads it back with `request`.
@MainActor
public final class NewRaceForm: NSView {
    /// An account to offer: its title and folder (nil: ~/.claude).
    public struct Account: Equatable {
        public let title: String
        public let dir: String?
        public init(title: String, dir: String?) {
            self.title = title
            self.dir = dir
        }
    }

    /// Model names offered; any other can be typed.
    public static let models = ["", "opus", "sonnet", "haiku"]

    private let accounts: [Account]
    private let machines: [String]
    private let maxAgents: Int
    let nameField = NSTextField()
    let baseField = NSTextField()
    let promptView = NSTextView()
    private let count = NSPopUpButton()
    private let rows = NSStackView()
    private(set) var contenderRows: [(account: NSPopUpButton, model: NSComboBox, machine: NSPopUpButton)] = []

    /// `machines`: "Run on" choices besides this Mac (hosts and tailnet machines).
    public init(accounts: [Account], machines: [String], base: String, maxAgents: Int, defaultCount: Int = 3) {
        self.accounts = accounts.isEmpty ? [Account(title: "~/.claude", dir: nil)] : accounts
        self.machines = machines
        self.maxAgents = max(2, maxAgents)
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        build(base: base, count: min(max(2, defaultCount), self.maxAgents))
    }

    required init?(coder: NSCoder) { nil }

    /// Where the keyboard starts.
    public var firstField: NSView { nameField }

    private func build(base: String, count initial: Int) {
        nameField.placeholderString = T("Race name (the worktrees are name-1, name-2…)", "Nome da corrida (as worktrees são nome-1, nome-2…)")
        baseField.stringValue = base
        promptView.isRichText = false
        promptView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        promptView.isAutomaticQuoteSubstitutionEnabled = false
        promptView.isAutomaticDashSubstitutionEnabled = false
        let scroll = NSScrollView()
        scroll.documentView = promptView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        promptView.autoresizingMask = [.width]
        promptView.minSize = NSSize(width: 0, height: 140)
        promptView.isVerticallyResizable = true
        scroll.heightAnchor.constraint(equalToConstant: 140).isActive = true
        count.addItems(withTitles: (2...maxAgents).map { T("\($0) agents", "\($0) agentes") })
        count.selectItem(at: initial - 2)
        count.target = self
        count.action = #selector(countChanged)
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        let stack = NSStackView(views: [
            labeled(T("Name", "Nome"), nameField), NSTextField(labelWithString: T("Prompt (the same for every agent)", "Prompt (o mesmo para todos os agentes)")),
            scroll, labeled(T("From branch", "Da branch"), baseField), labeled(T("Agents", "Agentes"), count), rows,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setRows(initial)
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 90).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return NSStackView(views: [label, control])
    }

    @objc private func countChanged() { setRows(count.indexOfSelectedItem + 2) }

    /// Fills the form as the owner would type it: the race's test in the app
    /// (CADEX_PERF_RACE_FORM, `../../app/RacePerfHooks.swift`). `accounts`:
    /// one folder per row (nil, the default account); a folder not offered is skipped.
    public func fill(name: String, prompt: String, count n: Int, accounts dirs: [String?], model: String) {
        nameField.stringValue = name
        promptView.string = prompt
        choose(count: n)
        for (row, dir) in zip(contenderRows, dirs) {
            if let index = accounts.firstIndex(where: { $0.dir == dir }) { row.account.selectItem(at: index) }
            row.model.stringValue = model
        }
    }

    /// The count popup's choice (tests set it as the owner would).
    func choose(count n: Int) {
        count.selectItem(at: n - 2)
        countChanged()
    }

    func setRows(_ n: Int) {
        while contenderRows.count < n {
            let index = contenderRows.count
            let account = NSPopUpButton()
            // One item per account, even with the same name: addItems(withTitles:)
            // drops repeats, and the rows would stop matching `accounts`
            // (found 2026-11-16: an account with no name came out blank).
            for title in Self.titles(accounts) { account.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
            account.selectItem(at: index % accounts.count)
            let model = NSComboBox()
            model.addItems(withObjectValues: Self.models.map { $0.isEmpty ? T("default", "padrão") : $0 })
            model.selectItem(at: 0)
            model.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let machine = NSPopUpButton()
            machine.addItems(withTitles: [T("This Mac", "Este Mac")] + machines)
            let row = NSStackView(views: [NSTextField(labelWithString: "#\(index + 1)"), account, model, machine])
            rows.addArrangedSubview(row)
            contenderRows.append((account, model, machine))
        }
        while contenderRows.count > n {
            contenderRows.removeLast()
            rows.arrangedSubviews.last.map { $0.removeFromSuperview() }
        }
    }

    /// Each account's title: its name, else its folder's; a repeat gets the folder too.
    static func titles(_ accounts: [Account]) -> [String] {
        let base = accounts.map { $0.title.isEmpty ? (($0.dir ?? "~/.claude") as NSString).lastPathComponent : $0.title }
        return zip(base, accounts).map { title, account in
            base.filter { $0 == title }.count > 1 ? title + " · " + ((account.dir ?? "~/.claude") as NSString).lastPathComponent : title
        }
    }

    /// What the owner chose; the app adds the repository and the caps.
    public func request(repository: String, caps: Caps) -> RaceRequest {
        let agents = contenderRows.map { row -> AgentChoice in
            let account = accounts[max(0, row.account.indexOfSelectedItem)]
            let typed = row.model.stringValue.trimmingCharacters(in: .whitespaces)
            let model = typed == T("default", "padrão") ? "" : typed
            let machine = row.machine.indexOfSelectedItem <= 0 ? "" : machines[row.machine.indexOfSelectedItem - 1]
            return AgentChoice(account: account.dir, model: model, machine: machine)
        }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        return RaceRequest(name: name.isEmpty ? "race" : name, prompt: promptView.string, repository: repository,
                           base: baseField.stringValue.trimmingCharacters(in: .whitespaces), agents: agents, caps: caps)
    }
}
