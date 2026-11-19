//! Extra host folders a jailed run may mount (`--jail-map`,
//! `--jail-rw-map`, remembered answers): refused when they are the checkout,
//! the home, a credential store or memory's data, by path and again after
//! resolving links.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged), crates/ai-memory-cli/src/commands/
//! jail_folders.rs: `ExtraFolder`, `upsert`, `FolderRefusal`, `FolderRules`,
//! `SENSITIVE_HOME_DIRS`, `ProtectedPaths`, `canonical`,
//! `validate_extra_folder`, `refuse` and `absolutize`. Changed for Cadex
//! (2026-11-16): the protected list adds Cadex's own folder (the owner's
//! data, sockets and session tokens) and macOS's ai-memory data folder.
//! Not ported: the interactive folder picker (`pick_folders`,
//! `PickerState`, a crossterm raw-mode TUI; crossterm is not in this
//! crate's tree), so the checklist's `f` names the flags instead.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// One extra folder to mount into the jail.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct ExtraFolder {
    pub(crate) path: PathBuf,
    #[serde(default)]
    pub(crate) writable: bool,
}

impl ExtraFolder {
    /// The folder's name and mode, e.g. `ai-jail (ro)`.
    pub(crate) fn label(&self) -> String {
        let name = self.path.file_name().map_or_else(|| self.path.display().to_string(), |n| n.to_string_lossy().into_owned());
        format!("{name} ({})", if self.writable { "rw" } else { "ro" })
    }
}

/// Add `folder`, replacing an earlier entry for the same path.
pub(crate) fn upsert(folders: &mut Vec<ExtraFolder>, folder: ExtraFolder) {
    folders.retain(|existing| existing.path != folder.path);
    folders.push(folder);
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum FolderRefusal {
    Missing,
    NotADirectory,
    Sensitive(PathBuf),
    IsCheckout,
}

impl std::fmt::Display for FolderRefusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Missing => f.write_str("the folder does not exist"),
            Self::NotADirectory => f.write_str("it is not a folder"),
            Self::Sensitive(path) => write!(f, "it would expose {}", path.display()),
            Self::IsCheckout => f.write_str("the checkout is already mounted"),
        }
    }
}

pub(crate) struct FolderRules<'a> {
    pub(crate) home: Option<&'a Path>,
    pub(crate) data_dir: &'a Path,
    pub(crate) checkout_root: &'a Path,
}

const SENSITIVE_HOME_DIRS: &[&str] = &[
    ".ssh",
    ".gnupg",
    ".aws",
    ".kube",
    ".config/gh",
    ".config/gcloud",
    ".docker",
    ".local/share/ai-memory",
    "Library/Application Support/ai-memory",
    "Library/Application Support/Cadex",
];

struct ProtectedPaths {
    home: Option<PathBuf>,
    checkout: PathBuf,
    protected: Vec<PathBuf>,
    resolved_home: Option<PathBuf>,
    resolved_checkout: PathBuf,
    resolved_protected: Vec<PathBuf>,
}

fn canonical(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_owned())
}

impl ProtectedPaths {
    fn new(rules: &FolderRules<'_>, cwd: &Path) -> Self {
        let home = rules.home.map(|home| absolutize(home, cwd, None));
        let checkout = absolutize(rules.checkout_root, cwd, None);
        let mut protected = home.iter().flat_map(|home| SENSITIVE_HOME_DIRS.iter().map(|dir| home.join(dir))).collect::<Vec<_>>();
        protected.push(absolutize(rules.data_dir, cwd, None));
        Self {
            resolved_home: home.as_deref().map(canonical),
            resolved_checkout: canonical(&checkout),
            resolved_protected: protected.iter().map(|path| canonical(path)).collect(),
            home,
            checkout,
            protected,
        }
    }

    fn check(&self, path: &Path) -> Result<(), FolderRefusal> {
        let metadata = std::fs::metadata(path).map_err(|_| FolderRefusal::Missing)?;
        if !metadata.is_dir() {
            return Err(FolderRefusal::NotADirectory);
        }
        refuse(path, self.home.as_deref(), &self.checkout, &self.protected)?;
        refuse(&canonical(path), self.resolved_home.as_deref(), &self.resolved_checkout, &self.resolved_protected).map_err(
            |refusal| match refusal {
                FolderRefusal::Sensitive(hit) => FolderRefusal::Sensitive(
                    self.resolved_protected.iter().position(|c| *c == hit).map_or(hit, |i| self.protected[i].clone()),
                ),
                other => other,
            },
        )
    }
}

/// Absolutize `raw` against `cwd` lexically and refuse what must not mount.
pub(crate) fn validate_extra_folder(raw: &Path, cwd: &Path, rules: &FolderRules<'_>) -> Result<PathBuf, FolderRefusal> {
    let path = absolutize(raw, cwd, rules.home);
    ProtectedPaths::new(rules, cwd).check(&path)?;
    Ok(path)
}

fn refuse(path: &Path, home: Option<&Path>, checkout: &Path, protected: &[PathBuf]) -> Result<(), FolderRefusal> {
    if path.starts_with(checkout) {
        return Err(FolderRefusal::IsCheckout);
    }
    if path.parent().is_none() || home == Some(path) {
        return Err(FolderRefusal::Sensitive(path.to_owned()));
    }
    match protected.iter().find(|guarded| path.starts_with(guarded) || guarded.starts_with(path)) {
        Some(guarded) => Err(FolderRefusal::Sensitive(guarded.clone())),
        None => Ok(()),
    }
}

fn absolutize(raw: &Path, cwd: &Path, home: Option<&Path>) -> PathBuf {
    let expanded = match (raw.strip_prefix("~"), home) {
        (Ok(rest), Some(home)) => home.join(rest),
        _ => raw.to_owned(),
    };
    ai_memory_workstream::clean_path(&cwd.join(expanded))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn siblings_mount_and_the_checkout_home_and_secrets_do_not() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path().join("home");
        let checkout = home.join("code/app");
        let sibling = home.join("code/lib");
        let data = home.join("Library/Application Support/Cadex/memory");
        for dir in [&checkout, &sibling, &data, &home.join(".ssh")] {
            std::fs::create_dir_all(dir).unwrap();
        }
        let rules = FolderRules { home: Some(&home), data_dir: &data, checkout_root: &checkout };
        assert_eq!(validate_extra_folder(Path::new("../lib"), &checkout, &rules), Ok(sibling));
        assert_eq!(validate_extra_folder(Path::new("."), &checkout, &rules), Err(FolderRefusal::IsCheckout));
        assert!(matches!(validate_extra_folder(Path::new("~/.ssh"), &checkout, &rules), Err(FolderRefusal::Sensitive(_))));
        assert!(matches!(validate_extra_folder(Path::new("~"), &checkout, &rules), Err(FolderRefusal::Sensitive(_))));
        assert!(matches!(validate_extra_folder(&data, &checkout, &rules), Err(FolderRefusal::Sensitive(_))));
        assert_eq!(validate_extra_folder(Path::new("../nope"), &checkout, &rules), Err(FolderRefusal::Missing));
    }
}
