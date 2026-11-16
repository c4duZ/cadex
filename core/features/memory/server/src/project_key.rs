//! The project key of Claude's automatic memory folder (plan 22, phase C):
//! each session Cadex opens gets `autoMemoryDirectory` =
//! `<memory>/auto/[<account key>/]<project key>`, the app computing the key
//! (apps/macos/features/memory/MemoryProject.swift). The rule lives in both
//! languages and a test in each pins the same value, so they cannot drift:
//!
//! 1. Start at the session's folder, made canonical (realpath; as given if
//!    it does not resolve).
//! 2. Walk up to the first folder holding `.git`. A `.git` folder is the
//!    common dir; a `.git` file (a worktree) names its gitdir
//!    (`gitdir: <path>`, relative to the folder holding it), whose
//!    `commondir` file, when present, names the common dir (relative to the
//!    gitdir); without one the gitdir is the common dir.
//! 3. When the common dir is named `.git`, the root is its parent, made
//!    canonical: the main checkout, for every worktree and subfolder. Any
//!    other case (no `.git` above, a bare repository, a submodule) keeps
//!    the folder of step 1.
//! 4. The key: the first 16 hex digits of the SHA-256 of the root's path
//!    (its UTF-8 bytes, no trailing slash).
//!
//! It is the `git rev-parse --git-common-dir` answer that project_paths.rs
//! `main_repo_root` asks git for, read from the files instead: the app
//! computes it at every launch and should not spawn git for it.
//!
//! The engine itself only needs step 4 (auto_wiki.rs checks a folder's name
//! against its project.json); steps 1 to 3 are here so the tests pin both
//! implementations to the same answers.

use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

#[cfg_attr(not(test), allow(dead_code))]
fn canonical(path: &Path) -> PathBuf {
    path.canonicalize().unwrap_or_else(|_| path.to_path_buf())
}

/// The common dir a worktree's `.git` file leads to.
#[cfg_attr(not(test), allow(dead_code))]
fn common_dir_of_file(dot_git: &Path, holder: &Path) -> Option<PathBuf> {
    let text = std::fs::read_to_string(dot_git).ok()?;
    let named = text.lines().find_map(|l| l.strip_prefix("gitdir:"))?.trim();
    let gitdir = holder.join(named);
    match std::fs::read_to_string(gitdir.join("commondir")) {
        Ok(common) => Some(gitdir.join(common.trim())),
        Err(_) => Some(gitdir),
    }
}

/// Steps 1 to 3: the main checkout of the repository `cwd` is in, or
/// `cwd` itself (canonical).
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn main_root(cwd: &Path) -> PathBuf {
    let start = canonical(cwd);
    let mut dir = start.as_path();
    loop {
        let dot_git = dir.join(".git");
        if let Ok(meta) = std::fs::metadata(&dot_git) {
            let common = if meta.is_dir() { Some(dot_git) } else { common_dir_of_file(&dot_git, dir) };
            let common = common.map(|c| canonical(&c));
            return common
                .filter(|c| c.file_name().is_some_and(|n| n == ".git"))
                .and_then(|c| c.parent().map(Path::to_path_buf))
                .unwrap_or(start);
        }
        match dir.parent() {
            Some(parent) => dir = parent,
            None => return start,
        }
    }
}

/// Step 4, for a root already found (the app writes it in each folder's
/// project.json).
pub(crate) fn key_of_root(root: &Path) -> String {
    let bytes = root.as_os_str().as_bytes();
    let trimmed = if bytes.len() > 1 { bytes.strip_suffix(b"/").unwrap_or(bytes) } else { bytes };
    let digest = Sha256::digest(trimmed);
    digest.iter().take(8).map(|b| format!("{b:02x}")).collect()
}

/// The key of the session folder `cwd`. The engine maps a folder back to
/// its project by the folder's project.json (auto_wiki.rs), so only the
/// tests ask; the rule is here to be pinned beside the app's.
#[cfg(test)]
pub(crate) fn key(cwd: &Path) -> String {
    key_of_root(&main_root(cwd))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    fn git(dir: &Path, args: &[&str]) {
        let ok = Command::new("git").arg("-C").arg(dir).args(args).output().unwrap().status.success();
        assert!(ok, "git {args:?}");
    }

    #[test]
    fn the_key_is_pinned_to_the_apps() {
        // The same value is pinned in apps/macos/features/memory/tests/main.swift.
        assert_eq!(key_of_root(Path::new("/Users/example/acme")), "9db38d359c2297b1");
        assert_eq!(key_of_root(Path::new("/Users/example/acme/")), "9db38d359c2297b1");
    }

    #[test]
    fn a_worktree_and_a_subfolder_share_the_main_checkout_s_key() {
        let tmp = tempfile::tempdir().unwrap();
        let repo = tmp.path().join("acme");
        std::fs::create_dir_all(repo.join("src/deep")).unwrap();
        git(&repo, &["init", "-q"]);
        git(&repo, &["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"]);
        let tree = tmp.path().join("acme-task");
        git(&repo, &["worktree", "add", "-q", tree.to_str().unwrap()]);

        let root = repo.canonicalize().unwrap();
        assert_eq!(main_root(&repo), root);
        assert_eq!(main_root(&repo.join("src/deep")), root);
        assert_eq!(main_root(&tree), root, "a worktree is its main checkout's project");
        assert_eq!(key(&tree), key(&repo));
        // The files say what git says (project_paths.rs asks git).
        let by_git = crate::project_paths::main_repo_root(&tree).unwrap().canonicalize().unwrap();
        assert_eq!(main_root(&tree), by_git);

        let outside = tmp.path().join("loose");
        std::fs::create_dir_all(&outside).unwrap();
        assert_eq!(main_root(&outside), outside.canonicalize().unwrap(), "outside git: the folder itself");
        assert_ne!(key(&outside), key(&repo));
    }
}
