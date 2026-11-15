import Foundation

/// Which app the agent may act in (docs/adr/0026-computer-use.md): never the
/// blocked ones (System Settings, Keychain Access, Terminal, Cadex itself,
/// and the owner's own list); the ones the owner allowed; the rest ask at
/// the first action.
public struct ComputerUseRules: Equatable, Sendable {
    public static let alwaysBlocked: Set<String> = ["com.apple.systempreferences", "com.apple.Preferences", "com.apple.keychainaccess", "com.apple.Terminal"]

    public var allowed: Set<String> = []
    public var blocked: Set<String> = []
    /// Cadex's own bundle id: the agent has Cadex by its tools (ADR 0024).
    public var own: String = Bundle.main.bundleIdentifier ?? "io.github.c4duz.cadex"

    public enum Decision: Equatable, Sendable { case blocked, allowed, ask }

    public init(allowed: Set<String> = [], blocked: Set<String> = [], own: String = Bundle.main.bundleIdentifier ?? "io.github.c4duz.cadex") {
        self.allowed = allowed
        self.blocked = blocked
        self.own = own
    }

    public func decide(_ bundleID: String) -> Decision {
        if Self.alwaysBlocked.contains(bundleID) || blocked.contains(bundleID) || bundleID == own || bundleID.isEmpty { return .blocked }
        return allowed.contains(bundleID) ? .allowed : .ask
    }
}
