import Foundation

/// Where a task can run (docs/spec/worktrees.md, "Rodar em"; ADR 0031):
/// this Mac, or another machine reached by `ssh <destination>`.
public struct RunTarget: Equatable, Hashable, Codable, Sendable {
    /// What the owner reads: "pc", "vps-a".
    public var label: String
    /// What ssh is given: a host of ~/.ssh/config, or `user@pc.tail1234.ts.net`.
    public var destination: String

    public init(label: String, destination: String) {
        self.label = label
        self.destination = destination
    }
}

/// The shell text "Run on" sends to the other machine, pure and tested by
/// running it on this one. Every value goes in single quotes; nothing of
/// the owner's is copied there (no account, no key, no .worktreeinclude).
public enum RemoteTaskScript {
    /// `'text'`, with each `'` closed, escaped and opened again.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Sets `$repo` from a folder that may start with `~/` (a quoted `~` is
    /// not expanded by sh, so it becomes `$HOME`).
    static func repoLine(_ folder: String) -> String {
        "repo=\(quote(folder)); case \"$repo\" in \"~\") repo=\"$HOME\";; \"~/\"*) repo=\"$HOME/${repo#\\~/}\";; esac"
    }

    /// Finds the repository (or clones `origin` there when `clone`), fetches,
    /// and adds the worktree `<repo>.worktrees/<branch>` from origin's
    /// `base` (else the local one, else HEAD), the branch made unique with
    /// "-2", "-3"… as here. Prints `CADEX_TASK_PATH=` and
    /// `CADEX_TASK_BRANCH=`; exits 3 printing `CADEX_NO_REPO` when the
    /// folder holds no repository and cloning was not asked.
    public static func prepare(folder: String, origin: String?, clone: Bool, branch: String, base: String) -> String {
        let cloneLine = clone && origin != nil
            ? "git clone --quiet \(quote(origin!)) \"$repo\""
            : "echo CADEX_NO_REPO; exit 3"
        return """
        set -e
        \(repoLine(folder))
        if [ ! -e "$repo/.git" ]; then \(cloneLine); fi
        cd "$repo"
        git fetch --quiet origin 2>/dev/null || true
        base=\(quote(base))
        if [ -n "$base" ] && git rev-parse --verify --quiet "refs/remotes/origin/$base" >/dev/null; then start="origin/$base"
        elif [ -n "$base" ] && git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then start="$base"
        else start=HEAD; fi
        root="$repo.worktrees"
        b=\(quote(branch)); n=2
        while git show-ref --verify --quiet "refs/heads/$b" || [ -e "$root/$b" ]; do b=\(quote(branch))-$n; n=$((n+1)); done
        mkdir -p "$root"
        git worktree add --quiet -b "$b" "$root/$b" "$start"
        echo "CADEX_TASK_PATH=$root/$b"
        echo "CADEX_TASK_BRANCH=$b"
        """
    }

    /// Takes the remote worktree away; git refuses one with changes, and
    /// that message comes back as it is. The branch stays.
    public static func remove(folder: String, path: String) -> String {
        """
        set -e
        \(repoLine(folder))
        cd "$repo"
        git worktree remove \(quote(path))
        echo CADEX_REMOVED
        """
    }

    /// The task's tab: in the worktree, the setup hooks and then `claude`,
    /// with the remote's own login; when it ends, a login shell stays.
    /// Through a login shell, so the PATH has where `claude` was installed.
    public static func agent(path: String, hooks: [String]) -> String {
        let steps = ["cd \(quote(path))"] + hooks + ["claude"]
        return login(steps.joined(separator: " && ") + "; exec \"$SHELL\" -l")
    }

    /// worktrees.open-remote-shell: a login shell in the worktree.
    public static func shell(path: String) -> String {
        login("cd \(quote(path)) && exec \"$SHELL\" -l")
    }

    static func login(_ inner: String) -> String {
        "exec \"$SHELL\" -l -c \(quote(inner))"
    }

    /// What the terminal types: `ssh -t '<destination>' '<remote command>'`.
    public static func sshLine(_ target: RunTarget, _ remote: String) -> String {
        "ssh -t \(quote(target.destination)) \(quote(remote))"
    }

    /// The path and branch the preparation printed; nil without them.
    public static func made(_ output: String) -> (path: String, branch: String)? {
        var path: String?, branch: String?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("CADEX_TASK_PATH=") { path = String(line.dropFirst(16)) }
            if line.hasPrefix("CADEX_TASK_BRANCH=") { branch = String(line.dropFirst(18)) }
        }
        guard let path, let branch, !path.isEmpty, !branch.isEmpty else { return nil }
        return (path, branch)
    }
}
