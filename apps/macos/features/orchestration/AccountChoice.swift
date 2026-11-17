import Foundation

/// An account of Claude Code as the forms of runs and automations offer it (it was the New Race
/// form's, which left in plan 29 for the New Task sheet): its name and folder, nil for the default.
public struct AccountChoice: Equatable, Sendable {
    public let title: String
    public let dir: String?

    public init(title: String, dir: String?) {
        self.title = title
        self.dir = dir
    }

    /// The models the forms offer; empty is the account's own default.
    public static let models = ["", "opus", "sonnet", "haiku"]

    /// The names to show: two accounts of the same name get their folder after it.
    public static func titles(_ accounts: [AccountChoice]) -> [String] {
        let base = accounts.map { $0.title.isEmpty ? (($0.dir ?? "~/.claude") as NSString).lastPathComponent : $0.title }
        return zip(base, accounts).map { title, account in
            base.filter { $0 == title }.count > 1 ? title + " · " + ((account.dir ?? "~/.claude") as NSString).lastPathComponent : title
        }
    }
}
