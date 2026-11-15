import AppKit
import CommandPalette
import Icons
import Strings

/// The comment commands (docs/spec/review.md, ADR 0005). The app gives
/// what each acts on, since the review tab is another feature's: `c` adds
/// a comment only with the review in focus (elsewhere the key goes on).
public enum ReviewCommentCommands {
    public struct Actions {
        public var add: @MainActor () -> Void
        public var edit: @MainActor () -> Void
        public var delete: @MainActor () -> Void
        public var send: @MainActor () -> Void
        public var clear: @MainActor () -> Void
        public var showSent: @MainActor () -> Void
        /// Why each can't run now (nil: it can).
        public var canAdd: @MainActor () -> String?
        public var canEdit: @MainActor () -> String?
        public var canSend: @MainActor () -> String?
        public var canShowSent: @MainActor () -> String?

        public init(add: @escaping @MainActor () -> Void, edit: @escaping @MainActor () -> Void, delete: @escaping @MainActor () -> Void,
                    send: @escaping @MainActor () -> Void, clear: @escaping @MainActor () -> Void, showSent: @escaping @MainActor () -> Void,
                    canAdd: @escaping @MainActor () -> String?, canEdit: @escaping @MainActor () -> String?,
                    canSend: @escaping @MainActor () -> String?, canShowSent: @escaping @MainActor () -> String?) {
            self.add = add
            self.edit = edit
            self.delete = delete
            self.send = send
            self.clear = clear
            self.showSent = showSent
            self.canAdd = canAdd
            self.canEdit = canEdit
            self.canSend = canSend
            self.canShowSent = canShowSent
        }
    }

    @MainActor
    public static func all(_ actions: Actions) -> [Command] {
        let keywords = ["review", "comment", "revisão", "comentário"]
        return [
            Command(id: "review.add-comment", title: T("Comment on Lines", "Comentar as linhas"), keywords: keywords, category: .edit,
                    defaultShortcut: "c", action: .run { actions.add() }, unavailableReason: actions.canAdd),
            Command(id: "review.edit-comment", title: T("Edit Comment", "Editar o comentário"), keywords: keywords, category: .edit,
                    action: .run { actions.edit() }, unavailableReason: actions.canEdit),
            Command(id: "review.delete-comment", title: T("Delete Comment", "Apagar o comentário"), keywords: keywords, category: .edit,
                    action: .run { actions.delete() }, unavailableReason: actions.canEdit),
            Command(id: "review.send-comments", title: T("Send Comments to Agent", "Enviar os comentários ao agente"),
                    keywords: keywords + ["send", "agent", "enviar", "agente"], category: .edit,
                    action: .run { actions.send() }, unavailableReason: actions.canSend),
            Command(id: "review.clear-comments", title: T("Clear Comments", "Apagar os comentários"), keywords: keywords + ["clear", "limpar"],
                    category: .edit, action: .run { actions.clear() }, unavailableReason: actions.canSend),
            Command(id: "review.show-sent", title: T("Show Sent Comments", "Mostrar os comentários enviados"),
                    keywords: keywords + ["history", "sent", "histórico", "enviados"], category: .edit,
                    action: .run { actions.showSent() }, unavailableReason: actions.canShowSent),
        ]
    }
}

/// The history of what was sent: each batch on the palette; choosing one
/// copies its text again.
@MainActor
public final class SentCommentsSource: PaletteSource {
    private let sent: [ReviewCommentStore.Sent]

    public init(sent: [ReviewCommentStore.Sent]) { self.sent = sent }

    public var placeholder: String { T("Sent comments", "Comentários enviados") }
    public var emptyText: String { T("Nothing sent yet", "Nada enviado ainda") }
    public var icon: Icon { .clipboardText }

    public func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let items = sent.enumerated().compactMap { index, batch -> PaletteItem? in
            let title = batch.comments.map(\.title).joined(separator: " · ")
            guard query.isEmpty || title.localizedCaseInsensitiveContains(query) || batch.text.localizedCaseInsensitiveContains(query) else { return nil }
            return PaletteItem(id: "\(index)", title: title, detail: formatter.string(from: batch.date) + " · " + T("↩ copies", "↩ copia"), icon: .clipboardText)
        }
        show(items, nil)
    }

    public func choose(_ item: PaletteItem) {
        guard let index = Int(item.id), sent.indices.contains(index) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sent[index].text, forType: .string)
    }

    public func stop() {}
}
