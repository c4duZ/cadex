//! The Claude Code account folders whose transcripts the import reads (plan
//! 22, phase C, "O histórico que já existe"): every folder the app shows as
//! an account, found by the same rule as the app's
//! apps/macos/features/agents/AgentSessions.swift (`AgentAccount.find`) and
//! AgentAccounts.swift (`AgentManagedAccounts.all`). Upstream's backfill reads
//! one folder (CLAUDE_CONFIG_DIR or ~/.claude); the owner works in several.

use std::path::{Path, PathBuf};

/// The account folders under `home`, in the app's order: ~/.claude when it
/// exists, each ~/.claude-* holding a .claude.json (by name), then each
/// folder Cadex made in Application Support/Cadex/accounts once Claude Code
/// wrote its .claude.json. `listed` (`--claude-dirs`) replaces the search.
pub(crate) fn find(home: &Path, listed: Option<&[PathBuf]>) -> Vec<PathBuf> {
    if let Some(dirs) = listed {
        return dirs.to_vec();
    }
    let mut dirs = Vec::new();
    let base = home.join(".claude");
    if base.exists() {
        dirs.push(base);
    }
    let mut named: Vec<PathBuf> = read_dir_sorted(home)
        .into_iter()
        .filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with(".claude-")))
        .collect();
    named.retain(|dir| dir.join(".claude.json").exists());
    dirs.extend(named);
    let managed = home.join("Library/Application Support/Cadex/accounts");
    dirs.extend(
        read_dir_sorted(&managed)
            .into_iter()
            .filter(|p| !p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with('.')))
            .filter(|dir| dir.join(".claude.json").exists()),
    );
    dirs
}

fn read_dir_sorted(dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut paths: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
    paths.sort();
    paths
}

/// An account's workspace name: its folder with every byte that is not an
/// ASCII letter or digit as "-", the rule of `cadex statusline`
/// (core/features/agent-tools/statusline.zig, accountKey) and of
/// SessionKit.accountKey, which the kit sends as `workspace=` when
/// memory.shareAcrossAccounts is off.
pub(crate) fn key(dir: &Path) -> String {
    let text = dir.to_string_lossy();
    let trimmed = if text.len() > 1 { text.trim_end_matches('/') } else { &text };
    trimmed.bytes().map(|b| if b.is_ascii_alphanumeric() { b as char } else { '-' }).collect()
}

/// The accounts a workspace reads: all of them for the shared `default`
/// (or none named), only the one whose key is the workspace otherwise.
pub(crate) fn for_workspace(dirs: &[PathBuf], workspace: Option<&str>) -> Vec<PathBuf> {
    match workspace.filter(|w| !w.is_empty() && *w != ai_memory_core::DEFAULT_WORKSPACE_NAME) {
        None => dirs.to_vec(),
        Some(name) => dirs.iter().filter(|dir| key(dir) == name).cloned().collect(),
    }
}

/// `--claude-dirs a:b:…`.
pub(crate) fn parse_list(text: &str) -> Vec<PathBuf> {
    text.split(':').filter(|s| !s.is_empty()).map(PathBuf::from).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_app_s_accounts_are_found_in_its_order() {
        let home = tempfile::tempdir().unwrap();
        let h = home.path();
        for dir in [".claude", ".claude-work", ".claude-old", "Library/Application Support/Cadex/accounts/team"] {
            std::fs::create_dir_all(h.join(dir)).unwrap();
        }
        std::fs::write(h.join(".claude-work/.claude.json"), "{}").unwrap();
        std::fs::write(h.join("Library/Application Support/Cadex/accounts/team/.claude.json"), "{}").unwrap();
        let found = find(h, None);
        assert_eq!(found, vec![
            h.join(".claude"),
            h.join(".claude-work"),
            h.join("Library/Application Support/Cadex/accounts/team"),
        ], ".claude-old has no .claude.json");
        let listed = parse_list("/a::/b");
        assert_eq!(find(h, Some(&listed)), vec![PathBuf::from("/a"), PathBuf::from("/b")]);
    }

    #[test]
    fn a_workspace_reads_only_its_account() {
        assert_eq!(key(Path::new("/Users/a/.claude-x")), "-Users-a--claude-x");
        assert_eq!(key(Path::new("/Users/a/My Acct_é/")), "-Users-a-My-Acct---");
        let dirs = vec![PathBuf::from("/Users/a/.claude"), PathBuf::from("/Users/a/.claude-x")];
        assert_eq!(for_workspace(&dirs, None), dirs);
        assert_eq!(for_workspace(&dirs, Some("default")), dirs);
        assert_eq!(for_workspace(&dirs, Some("-Users-a--claude-x")), vec![PathBuf::from("/Users/a/.claude-x")]);
        assert!(for_workspace(&dirs, Some("-nobody")).is_empty());
    }
}
