import AppKit
import Checks
import Foundation
@testable import Agents
@testable import Menus

// Managed accounts and the shared configuration (plan 18 phase C;
// docs/spec/agents.md, Contas gerenciadas), on a fake home folder.

/// A ~/.claude with shared things (skills, settings, a tool's folder) and
/// the account's own state, which must never be linked.
func fakeSource() -> String {
    let home = NSTemporaryDirectory() + "cadex-accounts-\(UUID().uuidString)"
    write(home + "/.claude/settings.json", #"{"hooks":{}}"#)
    write(home + "/.claude/CLAUDE.md", "# mine")
    write(home + "/.claude/skills/one/SKILL.md", "one")
    write(home + "/.claude/gsd-core/x.js", "")
    for state in ["projects/p/a.jsonl", "sessions/1.json", "history.jsonl", ".credentials.json", "daemon-auth-status.json",
                  ".last-cleanup", "remote-settings.json", "policy-limits.json", "mcp-needs-auth-cache.json", "telemetry/t"] {
        write(home + "/.claude/" + state, "")
    }
    return home
}

/// Moves into a fake trash, so tests never touch the real one.
func fakeTrash(_ home: String) -> (String) throws -> Void {
    { path in
        try? fm.createDirectory(atPath: home + "/Trash", withIntermediateDirectories: true)
        try fm.moveItem(atPath: path, toPath: home + "/Trash/" + UUID().uuidString + "-" + (path as NSString).lastPathComponent)
    }
}

func link(_ path: String) -> String? { try? fm.destinationOfSymbolicLink(atPath: path) }

let accountChecks: [(name: String, body: Checks.Body)] = [
    ("a new account: a short folder in Cadex's, linked to everything but the account's state", {
        let home = fakeSource()
        defer { try? fm.removeItem(atPath: home) }
        let dir = try AgentManagedAccounts.create(name: "Trabalho Ágil!", home: home)
        expect(dir == home + "/Library/Application Support/Cadex/accounts/trabalho-agil", dir)
        for name in ["settings.json", "CLAUDE.md", "skills", "gsd-core"] {
            expect(link(dir + "/" + name) == home + "/.claude/" + name, "\(name) is a link to the source")
        }
        let present = try fm.contentsOfDirectory(atPath: dir)
        for state in ["projects", "sessions", "history.jsonl", ".credentials.json", "daemon-auth-status.json", ".last-cleanup",
                      "remote-settings.json", "policy-limits.json", "mcp-needs-auth-cache.json", "telemetry"] {
            expect(!present.contains(state), "\(state) is the account's own state")
        }
        expect(AgentManagedAccounts.isManaged(dir, home: home) && AgentManagedAccounts.all(home: home) == [dir])
        expect(throws: { try AgentManagedAccounts.create(name: "trabalho agil", home: home) }, "the name is taken")
        expect(throws: { try AgentManagedAccounts.create(name: "!!!", home: home) }, "nothing usable in the name")
    }),
    ("the account shows up once Claude Code writes its .claude.json, named after its folder", {
        let home = fakeSource()
        defer { try? fm.removeItem(atPath: home) }
        let dir = try AgentManagedAccounts.create(name: "work", home: home)
        expect(!AgentAccount.find(home: home).contains { $0.dir == dir }, "no .claude.json yet")
        write(dir + "/.claude.json", #"{"oauthAccount":{"organizationName":"a@b.c's Organization"}}"#)
        expect(AgentAccount.find(home: home).first { $0.dir == dir }?.name == "work")
    }),
    ("a skill added to the default account is there at once; a new top-level item waits for a sync", {
        let home = fakeSource()
        defer { try? fm.removeItem(atPath: home) }
        let dir = try AgentManagedAccounts.create(name: "work", home: home)
        write(home + "/.claude/skills/two/SKILL.md", "two")
        expect(fm.fileExists(atPath: dir + "/skills/two/SKILL.md"), "through the link")
        write(home + "/.claude/agents/a.md", "")
        let plan = AgentConfigShare.plan(account: dir, source: home + "/.claude", replacing: false)
        expect(plan.link == ["agents"] && plan.trash.isEmpty, "\(plan)")
        try AgentConfigShare.apply(plan, account: dir, source: home + "/.claude", trash: fakeTrash(home))
        expect(link(dir + "/agents") == home + "/.claude/agents")
        try fm.removeItem(atPath: home + "/.claude/CLAUDE.md")
        try AgentConfigShare.apply(AgentConfigShare.plan(account: dir, source: home + "/.claude", replacing: false),
                                   account: dir, source: home + "/.claude", trash: fakeTrash(home))
        expect(link(dir + "/CLAUDE.md") == nil, "a link whose item left the source goes")
    }),
    ("own copy stops following; following again sends the copy to the trash", {
        let home = fakeSource()
        defer { try? fm.removeItem(atPath: home) }
        let source = home + "/.claude"
        let dir = try AgentManagedAccounts.create(name: "work", home: home)
        try AgentConfigShare.ownCopy("settings.json", account: dir, source: source)
        expect(AgentConfigShare.item("settings.json", account: dir, source: source) == .own)
        write(source + "/settings.json", #"{"changed":true}"#)
        expect(String(decoding: fm.contents(atPath: dir + "/settings.json")!, as: UTF8.self) == #"{"hooks":{}}"#, "the copy no longer follows")
        expect(AgentConfigShare.plan(account: dir, source: source, replacing: false).link.isEmpty, "a sync keeps own copies")
        try AgentConfigShare.follow("settings.json", account: dir, source: source, trash: fakeTrash(home))
        expect(link(dir + "/settings.json") == source + "/settings.json")
        expect(((try? fm.contentsOfDirectory(atPath: home + "/Trash")) ?? []).contains { $0.hasSuffix("settings.json") }, "in the trash, not deleted")
    }),
    ("sharing into an existing account shows what becomes a link and trashes what was there", {
        let home = fakeSource()
        defer { try? fm.removeItem(atPath: home) }
        let source = home + "/.claude"
        let old = home + "/.claude-old"
        write(old + "/.claude.json", "{}")
        write(old + "/settings.json", "{}")
        write(old + "/projects/p/x.jsonl", "")
        expect(!AgentConfigShare.follows(account: old, source: source, managed: false))
        let plan = AgentConfigShare.plan(account: old, source: source, replacing: true)
        expect(plan.trash == ["settings.json"] && plan.link == ["CLAUDE.md", "gsd-core", "settings.json", "skills"], "\(plan)")
        try AgentConfigShare.apply(plan, account: old, source: source, trash: fakeTrash(home))
        expect(link(old + "/settings.json") == source + "/settings.json" && fm.fileExists(atPath: old + "/projects/p/x.jsonl"))
        expect(AgentConfigShare.follows(account: old, source: source, managed: false), "it follows now")
        expect(fm.contents(atPath: old + "/.claude.json") == Data("{}".utf8), "its .claude.json untouched")
    }),
    ("the active account's card says so; the card's menu sets it", {
        let usage = AgentUsageController.shared
        let account = AgentAccount(dir: "/x/.claude-active", name: "A", isDefault: false)
        var launched: String?
        usage.plans[account.dir] = "max"
        usage.activeAccount = account.dir
        usage.accounts = { [account] }
        usage.states[account.dir] = .noUsage
        @MainActor func rowsOf() -> [StatusCard.Row] {
            AgentAccountsCard.blocks([account], launch: { launched = $0.dir }, run: { _ in })
                .compactMap { if case .rows(let r) = $0 { return r } else { return nil } }.flatMap { $0 }
        }
        expect(rowsOf().first?.detail == "Max · active")
        usage.activeAccount = nil
        expect(rowsOf().first?.detail == "Max")
        // The card's account is a row: its click opens that account's agent (the Accounts page's
        // click, plan 26 phase E).
        rowsOf().first?.action?()
        expect(launched == account.dir, "the card's row opens the account's agent")
    }),
    ("the accounts card (the approved proposal): Accounts · N Claude, each account's percent and bar, the foot's three commands", {
        let usage = AgentUsageController.shared
        let a = AgentAccount(dir: "/z/.claude", name: "bkdg", isDefault: true)
        let b = AgentAccount(dir: "/z/.claude-fba", name: "fba", isDefault: false)
        usage.accounts = { [a, b] }
        usage.plans = [a.dir: "max", b.dir: "team"]
        usage.activeAccount = nil
        usage.states = [a.dir: .ready(AgentUsage(session: .init(percent: 84, resets: nil), week: .init(percent: 61, resets: nil), sonnetWeek: nil), Date()),
                        b.dir: .noUsage]
        var launched: [String] = [], ran: [String] = []
        let blocks = AgentAccountsCard.blocks(usage.visibleAccounts(), launch: { launched.append($0.dir) }, run: { ran.append($0) })
        guard case .header(let title, let detail, _) = blocks.first else { return expect(false) }
        expect(title == "Accounts" && detail == "2 Claude", "\(title) \(String(describing: detail))")
        let rows = blocks.compactMap { if case .rows(let r) = $0 { return r } else { return nil } }.flatMap { $0 }
        expect(rows.map(\.title) == ["bkdg", "fba"] && rows[0].value == "84%" && rows[0].warn && rows[0].detail == "Max" && rows[1].value == "—",
               "\(rows.map { [$0.title, $0.value ?? "", $0.detail ?? ""] })")
        let notes = blocks.compactMap { if case .note(let t, _) = $0 { return t } else { return nil } }
        expect(notes.first == "84% of the 5-hour window · 61% of the week", "\(notes)")
        rows[1].action?()
        guard case .actions(let actions) = blocks.last else { return expect(false) }
        actions.forEach { $0.run() }
        expect(launched == [b.dir] && ran == ["agents.open-account", "agents.add-account", "settings.open-agents"], "\(launched) \(ran)")
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] {
            let card = AgentAccountsCard.make(launch: { _ in }, run: { _ in }, close: {})
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(white: 0.1, alpha: 1).cgColor
            card.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(card)
            NSLayoutConstraint.activate([card.topAnchor.constraint(equalTo: view.topAnchor, constant: 14), card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
                                         card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14), card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)])
            view.layoutSubtreeIfNeeded()
            view.frame = NSRect(origin: .zero, size: view.fittingSize)
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/accounts-card.png"))
            }
        }
    }),
    ("the usage item's right click: New Sessions Use, the active account checked, a choice sets it", {
        let usage = AgentUsageController.shared
        let d = AgentAccount(dir: "/y/.claude", name: "D", isDefault: true)
        let w = AgentAccount(dir: "/y/.claude-w", name: "W", isDefault: false)
        usage.accounts = { [d, w] }
        usage.states = [d.dir: .noUsage, w.dir: .noUsage]
        usage.activeAccount = nil
        let strip = AgentUsageStrip()
        var menu = strip.activeMenu()
        expect(menu.map(\.title) == ["New Sessions Use", "D", "W"], "\(menu.map(\.title))")
        expect(menu[1].icon == .check && menu[2].icon == nil, "none chosen: the default account")
        var chosen: String?
        strip.onSetActive = { chosen = $0.dir }
        menu[2].action()
        expect(chosen == w.dir)
        usage.activeAccount = w.dir
        menu = strip.activeMenu()
        expect(menu[1].icon == nil && menu[2].icon == .check)
        usage.activeAccount = nil
    }),
    ("the account of a new session: the project's beats the active one, then the default", {
        let a = AgentAccount(dir: "/h/.claude", name: "d", isDefault: true)
        let b = AgentAccount(dir: "/h/.claude-b", name: "b", isDefault: false)
        let c = AgentAccount(dir: "/h/.claude-c", name: "c", isDefault: false)
        let pick = { (cwd: String, active: String?, projects: [String: String]) in
            AgentNewSession.account(cwd: cwd, accounts: [a, b, c], active: active, projects: projects, projectRoot: { _ in "/code/app" })?.dir
        }
        expect(pick("/code/app/src", "/h/.claude-b", ["/code/app": "/h/.claude-c"]) == "/h/.claude-c")
        expect(pick("/code/app/src", "/h/.claude-b", [:]) == "/h/.claude-b")
        expect(pick("/code/app/src", nil, [:]) == "/h/.claude")
        expect(pick("/code/app/src", "/h/.claude-gone", ["/code/app": "/h/.claude-gone"]) == "/h/.claude", "an account that left falls back")
    }),
]

@MainActor func expect(throws body: () throws -> Void, _ message: String) {
    do { try body(); expect(false, message) } catch {}
}
