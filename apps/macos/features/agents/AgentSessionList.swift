import AppKit
import Strings
import UILooks

/// The Sessions list of the Agents page: a title per project that folds it,
/// and a row per session whose click goes to its terminal while its arrow
/// unfolds its subagents. Each session shows its account's logo, and its
/// sign sits on the middle of the name's line (the owner, 2026-10-21: the
/// dot sat high, one click did two things and opening seemed to freeze).
extension AgentsView {
    func renderGroups(_ groups: [AgentsLayout.Group]) {
        var carets: [String: AgentCaret] = [:]
        for group in groups {
            let key = "project:" + group.project.root
            let open = !folded.contains(group.project.root)
            let caret = AgentCaret(open: open && unfolding != key, color: colors.secondary)
            carets[key] = caret
            add(header(group, caret: caret))
            guard open else { continue }
            var rows: [NSView] = []
            for session in group.sessions {
                let sessionKey = "session:" + session.id
                let shows = controller.openSession == session.id
                let sessionCaret = AgentCaret(open: shows && unfolding != sessionKey, color: colors.secondary)
                carets[sessionKey] = sessionCaret
                rows.append(row(for: session, project: group.project, caret: sessionCaret))
                guard shows else { continue }
                let reveal = AgentReveal(subagentRows(of: session))
                reveals[sessionKey] = reveal
                rows.append(reveal)
            }
            let reveal = AgentReveal(rows)
            reveals[key] = reveal
            add(reveal)
        }
        guard let key = unfolding else { return }
        unfolding = nil
        reveals[key]?.unfold()
        carets[key]?.turn(to: true)
    }

    private func header(_ group: AgentsLayout.Group, caret: AgentCaret) -> NSView {
        let line = NSStackView(views: [AgentText.icon(.folder, size: 13, color: colors.accent),
                                       AgentText.label(group.project.name, size: 12, weight: .semibold, color: colors.text),
                                       AgentText.label("\(group.sessions.count)", size: 11, color: colors.secondary),
                                       NSView(), caret])
        line.spacing = 7
        let row = AgentRow(line, inset: 6)
        row.toolTip = group.project.root
        row.hoverFill = colors.fill.withAlphaComponent(0.35)
        let root = group.project.root
        row.onClick = { [weak self, weak caret] in if let caret { self?.fold(project: root, caret: caret) } }
        caret.onClick = row.onClick
        return Self.padded(row, top: 8)
    }

    private func row(for session: AgentSession, project: AgentProject, caret: AgentCaret) -> NSView {
        let kind: AgentSign.Kind = switch session.status {
        case .working: .working
        case .waiting: .waiting
        case .other: .unknown
        }
        let sign = AgentSign(kind, colors: colors, size: UILooks.pt(11))
        let name = AgentText.label(session.name, size: 13, weight: .medium, color: colors.text)
        let age = AgentText.label(AgentTime.short(since: session.since), size: 11, color: colors.secondary)
        age.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = NSStackView(views: [name, NSView(), age, caret])
        top.spacing = 6
        let logo = NSImageView(image: session.account.logo.image(size: UILooks.pt(11)))
        logo.contentTintColor = colors.secondary
        logo.setContentHuggingPriority(.required, for: .horizontal)
        let detail = AgentText.label(AgentsLayout.detail(session, project: project, inCadex: isInCadex(session)), size: 11, color: colors.secondary)
        let bottom = NSStackView(views: [logo, detail])
        bottom.spacing = 5
        let texts = NSStackView(views: [top, bottom])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        let line = NSView()
        for view in [sign, texts] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            line.addSubview(view)
        }
        NSLayoutConstraint.activate([
            top.widthAnchor.constraint(equalTo: texts.widthAnchor),
            sign.leadingAnchor.constraint(equalTo: line.leadingAnchor),
            sign.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            texts.leadingAnchor.constraint(equalTo: sign.trailingAnchor, constant: 8),
            texts.trailingAnchor.constraint(equalTo: line.trailingAnchor),
            texts.topAnchor.constraint(equalTo: line.topAnchor),
            texts.bottomAnchor.constraint(equalTo: line.bottomAnchor),
        ])
        let row = AgentRow(line)
        row.fill = controller.openSession == session.id ? colors.fill.withAlphaComponent(0.35) : nil
        row.hoverFill = colors.fill.withAlphaComponent(0.5)
        row.toolTip = "\(session.cwd)\n\(session.account.name) · pid \(session.pid)\n"
            + T("Click: go to its terminal. Arrow: its subagents.", "Clique: ir ao terminal dela. Seta: os subagentes.")
        row.onClick = { [weak self] in self?.onOpen?(session) }
        caret.onClick = { [weak self, weak caret] in if let caret { self?.toggleSubagents(of: session, caret: caret) } }
        return row
    }

    private func subagentRows(of session: AgentSession) -> [NSView] {
        let subagents = controller.subagents
        let title = subagents.isEmpty ? T("No subagents", "Nenhum subagente") : T("\(subagents.count) subagents", "\(subagents.count) subagentes")
        var rows: [NSView] = [AgentRow(AgentText.label(title, size: 11, color: colors.secondary), inset: 25)]
        for agent in subagents {
            let line = NSStackView(views: [AgentSign(agent.isRunning ? .working : .done, colors: colors, size: UILooks.pt(9)),
                                           AgentText.label(agent.description, size: 12, color: colors.text),
                                           NSView(),
                                           AgentText.label(AgentTime.short(since: agent.lastWrite), size: 11, color: colors.secondary)])
            line.spacing = 7
            let row = AgentRow(line, inset: 25)
            row.toolTip = "\(agent.type): \(agent.description)"
            row.hoverFill = colors.fill.withAlphaComponent(0.5)
            // A subagent runs inside its session: a click goes to that terminal.
            row.onClick = { [weak self] in self?.onOpen?(session) }
            rows.append(row)
        }
        return rows
    }

    /// Opens a session's subagents, unfolding, or folds them away first.
    private func toggleSubagents(of session: AgentSession, caret: AgentCaret) {
        let key = "session:" + session.id
        if controller.openSession == session.id, let reveal = reveals[key] {
            caret.turn(to: false)
            reveal.fold { [weak self] in self?.controller.toggle(session.id) }
        } else {
            unfolding = key
            controller.toggle(session.id)
        }
    }

    /// Folds a project's sessions under its title, or unfolds them.
    private func fold(project root: String, caret: AgentCaret) {
        let key = "project:" + root
        if folded.contains(root) {
            folded.remove(root)
            unfolding = key
            render()
        } else if let reveal = reveals[key] {
            caret.turn(to: false)
            reveal.fold { [weak self] in
                self?.folded.insert(root)
                self?.render()
            }
        }
    }

    private static func padded(_ view: NSView, top: CGFloat) -> NSView {
        let box = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: box.topAnchor, constant: top),
            view.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])
        return box
    }
}
