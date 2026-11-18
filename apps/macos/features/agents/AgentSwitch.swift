import AppKit
import CommandPalette
import Icons
import StateGlyph
import Strings
import UILooks

/// Switching a session's account (plan 33 E; docs/spec/agents.md, Trocar de conta): the session
/// ends, its handoff goes to the memory, and the same pane goes on in the other account with
/// "Continue in…". These are the rules; the terminals and the typing are the app's
/// (apps/macos/app/AccountSwitchWiring.swift).
public enum AgentSwitch {
    /// The most of the 5 hour session and the week, 0 to 100; nil with no numbers.
    public static func used(_ usage: AgentUsage?) -> Int? {
        guard let usage else { return nil }
        let windows = [usage.session?.percent, usage.week?.percent].compactMap { $0 }
        return windows.max().map { Int($0.rounded()) }
    }

    /// The account can do no more now: its session or its week at 100%.
    public static func atLimit(_ usage: AgentUsage?) -> Bool { (used(usage) ?? 0) >= 100 }

    /// Another account to go on in: the one with the most room under its limit; accounts with no
    /// numbers yet come after the known ones; nil when every other one is at its limit.
    public static func roomiest(_ accounts: [AgentAccount], except dir: String,
                                usage: (AgentAccount) -> AgentUsage?) -> (account: AgentAccount, used: Int?)? {
        let others = accounts.filter { $0.provider == .claude && $0.dir != dir }.map { ($0, used(usage($0))) }
        let open = others.filter { ($0.1 ?? 0) < 100 }
        return open.min { a, b in
            switch (a.1, b.1) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            default: return false
            }
        }.map { (account: $0.0, used: $0.1) }
    }

    /// A switch list's line: "session 15% · week 22% · back at 16:10 · ~/.claude-bkdg"; with no
    /// numbers, why ("usage shows after a session in Cadex").
    public static func detail(_ account: AgentAccount, usage: AgentUsage? = nil, now: Date = Date()) -> String {
        let numbers = usage ?? AgentUsage.current(of: account)
        var parts: [String] = []
        if let session = numbers?.session { parts.append(T("session \(Int(session.percent.rounded()))%", "sessão \(Int(session.percent.rounded()))%")) }
        if let week = numbers?.week { parts.append(T("week \(Int(week.percent.rounded()))%", "semana \(Int(week.percent.rounded()))%")) }
        if let back = numbers?.session?.resets, back > now, (numbers?.session?.percent ?? 0) >= 50 {
            parts.append(T("back at ", "volta às ") + back.formatted(date: .omitted, time: .shortened))
        }
        if parts.isEmpty { parts.append(T("usage shows after a session in Cadex", "o uso aparece depois de uma sessão no Cadex")) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folder = account.dir.hasPrefix(home) ? "~" + account.dir.dropFirst(home.count) : account.dir
        parts.append(folder.contains("/Application Support/Cadex/accounts/") ? T("Cadex account", "conta do Cadex") : String(folder))
        return parts.joined(separator: " · ")
    }

    /// The switch list as the approved proposal draws it (2026-11-18): each account with its logo
    /// in a square, the name over "session 15% · week 22% · back at 16:10 · ~/.claude-bkdg", a bar
    /// and the number on the right; the one in use last, dim, with "in use".
    @MainActor
    public static func rows(current: String?) -> [PaletteItem] {
        let accounts = AgentUsageController.shared.visibleAccounts().filter { $0.provider == .claude }
        let logo = PaletteItem.Tile.logo(ProviderLogo.claude.image(size: 12), ProviderLogo.claude.brandColor ?? .systemOrange)
        return (accounts.filter { $0.dir != current } + accounts.filter { $0.dir == current }).map { account in
            let inUse = account.dir == current
            let used = AgentSwitch.used(AgentUsage.current(of: account))
            var item = PaletteItem(id: account.dir, title: account.name, unavailableReason: inUse ? "" : nil)
            item.note = detail(account) + (inUse ? T(" · this session", " · esta sessão") : "")
            item.tile = logo
            if inUse {
                item.chip = T("in use", "em uso")
            } else {
                item.meter = used.map { Double($0) / 100 }
                item.meterText = used.map { "\($0)%" } ?? "—"
            }
            return item
        }
    }

    /// "32% used", or nothing with no numbers.
    public static func usedText(_ used: Int?) -> String {
        used.map { T("\($0)% used", "\($0)% usado") } ?? ""
    }
}

/// The notice at the foot of an agent's pane when its account reached the limit (plan 33 E): the
/// amber glyph, "<account> reached its limit", and a button to go on in the account with the most
/// room. The permission card's look (components.pane.permission), which left the pane in phase D.
@MainActor
public final class AgentLimitCard: NSView {
    typealias P = DesignTokens.Pane.Permission
    /// The account at its limit and the one offered: the app shows the card again only when they change.
    public let key: String

    public init(account: String, next: String, used: Int?, go: @escaping @MainActor () -> Void,
                close: @escaping @MainActor () -> Void) {
        key = account + "→" + next
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(P.radius)
        layer?.backgroundColor = P.bg.cgColor
        layer?.borderColor = P.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        if let shadow = P.shadow.first {
            layer?.shadowColor = shadow.color.cgColor
            layer?.shadowOpacity = 1
            layer?.shadowRadius = UILooks.pt(shadow.layerRadius)
            layer?.shadowOffset = shadow.offset
        }
        let glyph = StateGlyphView(size: P.glyph, state: .needs)
        glyph.widthAnchor.constraint(equalToConstant: UILooks.pt(P.glyph)).isActive = true
        glyph.heightAnchor.constraint(equalToConstant: UILooks.pt(P.glyph)).isActive = true
        let heading = NSTextField(labelWithString: T("\(account) reached its limit", "\(account) chegou ao limite"))
        heading.font = UILooks.font(P.Title.fontSize, weight: P.Title.weight)
        heading.textColor = DesignTokens.Color.textPrimary
        let note = NSTextField(labelWithString: [T("Go on in \(next)", "Continuar na \(next)"), AgentSwitch.usedText(used)]
            .filter { !$0.isEmpty }.joined(separator: " · "))
        note.font = UILooks.font(P.Command.fontSize)
        note.textColor = P.Command.color
        note.lineBreakMode = .byTruncatingTail
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let words = NSStackView(views: [heading, note])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = UILooks.pt(DesignTokens.Stroke.glyph)
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let goButton = DesignButton.make(T("Continue in \(next)", "Continuar na \(next)"), .primary, height: P.Allow.height, action: go)
        let closeButton = DesignButton.make(T("Not now", "Agora não"), .secondary, height: P.Deny.height, action: close)
        closeButton.layer?.backgroundColor = nil
        closeButton.layer?.borderColor = P.Deny.border.cgColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [glyph, words, spacer, goButton, closeButton])
        row.spacing = UILooks.pt(P.gap)
        row.edgeInsets = NSEdgeInsets(top: UILooks.pt(P.padding.top), left: UILooks.pt(P.padding.left),
                                      bottom: UILooks.pt(P.padding.bottom), right: UILooks.pt(P.padding.right))
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(heading.stringValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentLimitCard is created in code") }

    public override var mouseDownCanMoveWindow: Bool { false }
}
