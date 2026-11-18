import AppKit
import CommandPalette
import Strings

/// Plan 21 phase C's commands (ADR 0005): the conflict's blocks and Mark
/// Resolved on the conflict tab in front, and the image mode of the review
/// or the diff in front.
public enum ConflictCommands {
    @MainActor
    public static func all(conflict: @escaping @MainActor () -> ConflictDocument?, review: @escaping @MainActor () -> ReviewDocument?) -> [Command] {
        func needsConflict() -> String? { conflict() == nil ? T("No conflict open", "Nenhum conflito aberto") : nil }
        func onConflict(_ id: String, _ title: String, _ keywords: [String], _ body: @escaping @MainActor (ConflictDocument) -> Void) -> Command {
            Command(id: id, title: title, keywords: keywords + ["conflict", "merge", "conflito"], category: .file,
                    action: .run { if let doc = conflict() { body(doc) } }, unavailableReason: needsConflict)
        }
        return [
            onConflict("git.accept-ours", T("Keep Ours in Conflict", "Ficar com a nossa no conflito"), ["ours", "nossa"]) { $0.accept(.ours) },
            onConflict("git.accept-theirs", T("Keep Theirs in Conflict", "Ficar com a deles no conflito"), ["theirs", "deles"]) { $0.accept(.theirs) },
            onConflict("git.accept-both", T("Keep Both in Conflict", "Ficar com as duas no conflito"), ["both", "duas"]) { $0.accept(.both) },
            onConflict("git.mark-resolved", T("Mark Conflict Resolved", "Marcar o conflito como resolvido"), ["resolved", "resolvido", "stage"]) { $0.markResolved() },
            Command(id: "git.review-image-mode", title: T("Next Image Comparison Mode", "Próximo modo de comparar a imagem"),
                    keywords: ["image", "slide", "overlay", "imagem", "deslizar", "sobrepor"], category: .view,
                    action: .run {
                        review()?.cycleImageMode()
                    },
                    unavailableReason: {
                        review()?.hasImages == true ? nil : T("No image diff open", "Nenhum diff de imagem aberto")
                    }),
        ]
    }
}
