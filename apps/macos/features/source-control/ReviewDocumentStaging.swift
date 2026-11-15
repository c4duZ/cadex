import AppKit
import Strings

/// Stage and unstage from the review (docs/spec/source-control.md, Stage
/// parcial): the change under the cursor (git.review-stage-hunk) or the
/// marked lines (git.review-stage-lines), only in the cursor's file. The
/// lines map to the patch git stages from (ReviewStaging.swift) and go
/// through the core; the review reads itself again after.
extension ReviewDocument {
    /// The run of changed lines the cursor is on.
    public func stageChange(unstage: Bool) {
        guard text.layout.rows.indices.contains(text.cursor),
              case .line(_, _, _, _, let change?) = text.layout.rows[text.cursor] else {
            return say(T("Put the cursor on a change first", "Ponha o cursor numa mudança antes"))
        }
        let rows = text.layout.rows.indices.filter {
            if case .line(_, _, _, _, let other) = text.layout.rows[$0] { return other == change }
            return false
        }
        stage(rows, unstage: unstage)
    }

    /// The marked lines (the cursor's alone when none).
    public func stageMarked(unstage: Bool) {
        stage(text.marked, unstage: unstage)
    }

    private func stage(_ rows: [Int], unstage: Bool) {
        guard request.to == nil else {
            return say(T("Staging works on the work tree, not between two tips", "O stage vale na árvore de trabalho, não entre duas pontas"))
        }
        guard let first = rows.first, text.layout.rows.indices.contains(first) else { return }
        let file = ReviewLayout.file(of: text.layout.rows[first])
        let inFile = rows.filter { ReviewLayout.file(of: text.layout.rows[$0]) == file }
        let marked = ReviewStaging.marked(text.layout.rows, at: inFile, files: files)
        guard marked.contains(where: { $0.kind != .context }), files.indices.contains(file) else {
            return say(T("No changed line marked", "Nenhuma linha mudada marcada"))
        }
        let path = files[file].file.path
        let repo = GitRepository(root: request.repo)
        repo.queue.async { [weak self] in
            let outcome: String
            if let patch = repo.stagingPatch(path: path, staged: unstage) {
                let lines = ReviewStaging.indices(of: marked, in: patch, unstage: unstage)
                if lines.isEmpty {
                    outcome = unstage ? T("Nothing here is staged", "Nada disto está no stage")
                                      : T("Nothing here to stage: already staged or committed", "Nada aqui para o stage: já está no stage ou no commit")
                } else if let error = repo.applyLines(patch: patch, lines: lines, unstage: unstage) {
                    outcome = error
                } else {
                    outcome = unstage ? T("Unstaged \(lines.count) lines of \(path)", "\(lines.count) linhas de \(path) fora do stage")
                                      : T("Staged \(lines.count) lines of \(path)", "\(lines.count) linhas de \(path) no stage")
                }
            } else {
                outcome = T("Couldn't read the file's patch", "Não foi possível ler o patch do arquivo")
            }
            DispatchQueue.main.async { MainActor.assumeIsolated {
                self?.notice = outcome
                self?.load()
            } }
        }
    }
}
