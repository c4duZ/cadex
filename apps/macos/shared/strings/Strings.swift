import CCadex
import Foundation

/// The interface's language (docs/adr/0015-english-default-two-languages.md):
/// English by default, Portuguese as an option, read once at launch from
/// settings.json; changing it asks to reopen Cadex.
public enum Language: String, CaseIterable, Sendable {
    case en, pt
}

public enum Strings {
    /// Set by the app at launch, before any text is made, and not after:
    /// every view reads its texts once.
    nonisolated(unsafe) public static var language: Language = .en

    /// At launch: the interface and the core's few texts (a git message,
    /// the name of a pasted copy) in `language`.
    public static func setLanguage(_ language: Language) {
        self.language = language
        cadex_set_language(language.rawValue)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var counterparts: [String: String] = [:]

    /// The other language's version of a text T made: the palette finds a
    /// command by its title in either language.
    public static func counterpart(of text: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return counterparts[text]
    }

    static func remember(_ shown: String, _ other: String) {
        guard shown != other else { return }
        lock.lock()
        counterparts[shown] = other
        lock.unlock()
    }
}

/// A text of the interface, written in both languages where it is used
/// (ADR 0015): `T("Open file", "Abrir arquivo")`.
public func T(_ en: String, _ pt: String) -> String {
    let (shown, other) = Strings.language == .pt ? (pt, en) : (en, pt)
    Strings.remember(shown, other)
    return shown
}
