import AppKit
import Tabs
import UILooks

/// A race's board in a tab (orchestration.show-race). It reads the race
/// from the state and what the app knows of each contender (`live`) when it
/// opens and when `refresh` is called (an agent changed, a timer the app
/// keeps only while a board is open); closed, it lets go of everything.
@MainActor
public final class RaceBoardDocument: TabDocument {
    public let raceID: String
    public var onChange: (() -> Void)?
    public private(set) var title: String
    private let board = OrchestrationPage()
    private let actions: RaceBoardActions
    private let book: RaceBook
    private let live: (Contender) -> ContenderLive?
    /// The window's tabs close the document; the app counts open boards.
    public var onClose: (() -> Void)?

    public init(raceID: String, book: RaceBook, actions: RaceBoardActions,
                live: @escaping (Contender) -> ContenderLive?) {
        self.raceID = raceID
        self.book = book
        self.live = live
        self.actions = actions
        title = "Race"
        refresh()
    }

    public static func identity(for race: String) -> String { "race:\(race)" }
    public var identity: String { Self.identity(for: raceID) }
    public var view: NSView { board }
    public var hasUnsavedChanges: Bool { false }
    public var isPage: Bool { true }

    /// The contenders of the race, as the board last read them.
    public private(set) var contenders: [Contender] = []

    public func refresh() {
        guard let race: Race = try? book.store.get(.races, id: raceID) else { return }
        contenders = (try? book.contenders(of: raceID)) ?? []
        let columns = RaceColumns.make(race: race, contenders: contenders, live: live, now: Date())
        board.show(RaceBoardView.sections(race: race, columns: columns, contenders: contenders, actions: actions))
        if title != race.name {
            title = race.name
            onChange?()
        }
    }

    public func focus() { board.window?.makeFirstResponder(board) }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() { onClose?() }
}
