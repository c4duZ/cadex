import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The tasks page (docs/spec/worktrees.md): the window's repository's task
/// worktrees with their status and comment. A click opens one; the right
/// click sets its status, its comment, or takes it away. Reads only while
/// it shows.
@MainActor
public final class WorktreesView: NSView {
    public var text = NSColor.labelColor { didSet { render() } }
    public var secondary = NSColor.secondaryLabelColor { didSet { render() } }
    /// The window's repository, or nil outside one.
    public var repository: (() -> String?)?
    public var onOpen: ((TaskWorktree) -> Void)?
    /// "Review Changes": the task's review tab (the app runs git.review-open for it).
    public var onReview: ((TaskWorktree) -> Void)?
    public var onNewTask: (() -> Void)?
    public var onComment: ((TaskWorktree) -> Void)?
    public var onRemove: ((TaskWorktree) -> Void)?

    let controller = WorktreesController.shared
    private let stack = NSStackView()
    private var token: UUID?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateWatching() }
    public override func viewDidHide() { super.viewDidHide(); updateWatching() }
    public override func viewDidUnhide() { super.viewDidUnhide(); updateWatching() }

    func updateWatching() {
        let shows = window != nil && !isHiddenOrHasHiddenAncestor
        if shows, token == nil { token = controller.watch { [weak self] in self?.render() } }
        else if !shows, let id = token { controller.stop(id); token = nil }
    }

    func render() {
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        guard let repo = repository?() else {
            return add(label(T("Open a git repository to make tasks.", "Abra um repositório git para criar tarefas."), size: 12, color: secondary))
        }
        let tasks = controller.tasks(repo: repo)
        if tasks.isEmpty {
            add(label(T("No tasks yet.", "Nenhuma tarefa ainda."), size: 12, color: secondary))
            let button = NSButton(title: T("New Task", "Nova tarefa"), target: self, action: #selector(newTask))
            button.bezelStyle = .rounded
            return add(button)
        }
        for (task, info) in tasks { add(row(task, info)) }
    }

    private func row(_ task: TaskWorktree, _ info: TaskInfo?) -> NSView {
        let title = label(task.branch.isEmpty ? (task.path as NSString).lastPathComponent : task.branch, size: 12, weight: .semibold, color: text)
        let detail = [info?.status.title, info?.comment].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let box = NSStackView(views: [title, label(detail.isEmpty ? (task.path as NSString).abbreviatingWithTildeInPath : detail, size: 11, color: secondary)])
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 1
        let row = TaskRow(box)
        row.toolTip = task.path
        row.onClick = { [weak self] in self?.onOpen?(task) }
        row.onRightClick = { [weak self, weak row] in
            guard let self, let row else { return }
            PopupMenu.show(self.menu(task), below: row)
        }
        return row
    }

    func menu(_ task: TaskWorktree) -> [MenuEntry] {
        var entries = [MenuEntry(T("Open", "Abrir"), icon: .folderOpen) { [weak self] in self?.onOpen?(task) },
                       MenuEntry(T("Review Changes", "Revisar as mudanças"), icon: .gitDiff) { [weak self] in self?.onReview?(task) }, .separator]
        for status in TaskStatus.allCases {
            entries.append(MenuEntry(status.title, icon: controller.store.task(task.path)?.status == status ? .check : nil) { [weak self] in
                self?.controller.setStatus(status, of: task.path)
            })
        }
        entries += [.separator,
                    MenuEntry(T("Comment…", "Comentar…"), icon: .pencilSimple) { [weak self] in self?.onComment?(task) },
                    MenuEntry(T("Remove Task…", "Remover tarefa…"), icon: .trash) { [weak self] in self?.onRemove?(task) }]
        return entries
    }

    @objc private func newTask() { onNewTask?() }

    private func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -16).isActive = true
    }

    private func label(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = UILooks.font(size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

/// A clickable row: click opens, right click shows the menu.
private final class TaskRow: NSView {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    init(_ content: NSView) {
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 4), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseUp(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}
