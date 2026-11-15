import Foundation
import CCadex

/// The review's calls into the core (cadex_git_review_*, plan 21): the
/// base, the files changed against it, one file, and partial staging. Like
/// the rest of GitRepository, every call blocks on `git`: run on `queue`.
extension GitRepository {
    /// One changed file of the review.
    struct ReviewFile: Equatable, Sendable {
        /// A, M, D, R, T, or ? for a new file git does not know.
        let status: Character
        /// Nil for a binary.
        let added: Int?
        let removed: Int?
        let path: String
        let orig: String

        var isNew: Bool { status == "?" || status == "A" }
    }

    /// The base commit: the merge-base with the task's start branch (or the
    /// default branch). Nil when none.
    func reviewBase(start: String?) -> String? {
        Self.reviewText { cadex_git_review_base(root, start?.isEmpty == false ? start : nil, &$0, &$1) }
    }

    /// The files changed against `base`; `to` nil: the work tree.
    func reviewFiles(base: String, to: String?) -> [ReviewFile]? {
        Self.reviewText { cadex_git_review_files(root, base, to, &$0, &$1) }.map(Self.parseReviewFiles)
    }

    static func parseReviewFiles(_ text: String) -> [ReviewFile] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5, let status = f[0].first else { return nil }
            return ReviewFile(status: status, added: Int(f[1]), removed: Int(f[2]), path: f[3], orig: f[4])
        }
    }

    func reviewDiff(base: String, to: String?, path: String, orig: String) -> Diff? {
        var d = cadex_git_diff_sides()
        guard cadex_git_review_diff(root, base, to, path, orig.isEmpty ? nil : orig, &d) == CADEX_OK else { return nil }
        defer { cadex_git_diff_free(&d) }
        func string(_ p: UnsafeMutablePointer<UInt8>?, _ n: Int) -> String {
            guard let p else { return "" }
            return String(decoding: UnsafeBufferPointer(start: p, count: n), as: UTF8.self)
        }
        return Diff(before: string(d.before, d.before_len), after: string(d.after, d.after_len),
                    patch: string(d.patch, d.patch_len), binary: d.binary, tooLarge: d.too_large)
    }

    /// The patch to pick lines from: unstaged (a new file is made known
    /// with add -N) or staged.
    func stagingPatch(path: String, staged: Bool) -> String? {
        Self.reviewText { cadex_git_review_patch(root, path, staged, &$0, &$1) }
    }

    /// Stages (or unstages) the lines at `lines` of `patch`. Nil: done.
    func applyLines(patch: String, lines: [Int], unstage: Bool) -> String? {
        let bytes = Array(patch.utf8)
        let indices = lines.map { $0 }
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        let status = bytes.withUnsafeBufferPointer { patchBuffer in
            indices.withUnsafeBufferPointer { lineBuffer in
                cadex_git_review_apply(root, patchBuffer.baseAddress, patchBuffer.count, lineBuffer.baseAddress, lineBuffer.count, unstage, &out, &len)
            }
        }
        defer { cadex_free(out) }
        if status == CADEX_OK { return nil }
        guard let out else { return "git failed" }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }

    private static func reviewText(_ call: (inout UnsafeMutablePointer<UInt8>?, inout Int) -> cadex_status) -> String? {
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        guard call(&out, &len) == CADEX_OK else { return nil }
        guard let out else { return "" }
        defer { cadex_free(out) }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }
}
