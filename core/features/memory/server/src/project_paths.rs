//! The folders whose sessions belong to a project (plan 22, phase C): the
//! repository root, every folder under it and its git worktrees (plan 19 puts
//! a task's worktree outside the main checkout). Upstream's backfill matches
//! the exact cwd only, so a session opened in `src/` or in a task's worktree
//! never reached the project's memory.

use std::path::{Path, PathBuf};
use std::process::Command;

/// A project's folders, each as given and canonical (macOS /tmp is
/// /private/tmp, and a transcript records whichever the shell had).
#[derive(Debug, Clone)]
pub(crate) struct ProjectPaths {
    roots: Vec<PathBuf>,
}

fn git(dir: &Path, args: &[&str]) -> Option<String> {
    let out = Command::new("git").arg("-C").arg(dir).args(args).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

/// The main checkout of the repository `cwd` is in: the parent of
/// `git rev-parse --git-common-dir` (a worktree's common dir is the main
/// checkout's `.git`). `None` outside git, or for a bare repository.
pub(crate) fn main_repo_root(cwd: &Path) -> Option<PathBuf> {
    let common = git(cwd, &["rev-parse", "--path-format=absolute", "--git-common-dir"])?;
    let common = PathBuf::from(common.trim());
    (common.file_name()? == ".git").then(|| common.parent().map(Path::to_path_buf)).flatten()
}

/// The worktrees `git worktree list --porcelain` names for `root`, main first.
fn worktrees(root: &Path) -> Vec<PathBuf> {
    let Some(list) = git(root, &["worktree", "list", "--porcelain"]) else { return Vec::new() };
    list.lines().filter_map(|l| l.strip_prefix("worktree ")).map(PathBuf::from).collect()
}

/// `path` with its longest existing ancestor made canonical: a session's
/// folder may be gone (a removed task folder) while its parent is not.
fn canonical_lossy(path: &Path) -> Option<PathBuf> {
    path.ancestors().find_map(|base| {
        let rest = path.strip_prefix(base).ok()?;
        Some(base.canonicalize().ok()?.join(rest))
    })
}

impl ProjectPaths {
    /// `root` and its worktrees (none when it is not a git checkout).
    pub(crate) fn for_root(root: &Path) -> Self {
        let mut found = vec![root.to_path_buf()];
        found.extend(worktrees(root));
        let mut roots = Vec::new();
        for path in found {
            let canonical = path.canonicalize().ok();
            for p in std::iter::once(path).chain(canonical) {
                if !roots.contains(&p) {
                    roots.push(p);
                }
            }
        }
        Self { roots }
    }

    /// Whether a session recorded in `cwd` belongs here: `cwd` is one of the
    /// folders or inside one (by path components, so /a/bc is not in /a/b).
    pub(crate) fn contains(&self, cwd: &Path) -> bool {
        let canonical = canonical_lossy(cwd);
        let candidates = std::iter::once(cwd).chain(canonical.as_deref());
        candidates.into_iter().any(|c| self.roots.iter().any(|root| c.starts_with(root)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(dir: &Path, args: &[&str]) {
        let ok = Command::new("git").arg("-C").arg(dir).args(args).output().unwrap().status.success();
        assert!(ok, "git {args:?}");
    }

    #[test]
    fn a_repo_owns_its_subfolders_and_worktrees_and_nothing_beside_it() {
        let tmp = tempfile::tempdir().unwrap();
        let repo = tmp.path().join("acme");
        std::fs::create_dir_all(repo.join("src")).unwrap();
        run(&repo, &["init", "-q"]);
        run(&repo, &["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"]);
        let tree = tmp.path().join("acme-task");
        run(&repo, &["worktree", "add", "-q", tree.to_str().unwrap()]);

        let paths = ProjectPaths::for_root(&repo);
        assert!(paths.contains(&repo) && paths.contains(&repo.join("src")));
        assert!(paths.contains(&tree.join("deep/er")), "a worktree, even a folder not made yet");
        assert!(!paths.contains(&tmp.path().join("acme2")) && !paths.contains(tmp.path()));

        let main = main_repo_root(&tree).unwrap();
        assert_eq!(main.canonicalize().unwrap(), repo.canonicalize().unwrap());
        assert_eq!(main_repo_root(&repo.join("src")).unwrap().canonicalize().unwrap(), repo.canonicalize().unwrap());
        assert!(main_repo_root(tmp.path()).is_none());
    }
}
