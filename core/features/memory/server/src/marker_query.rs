//! The query pairs upstream's hook client adds from a repository's
//! `.ai-memory.toml` (`build_marker_query_suffix` in the cli's
//! hook_capture.rs at 411d90d, v3.5.0), added here to `/hook`, `/handoff` and
//! `/brief` before upstream's routes read them, since `cadex memory-hook`
//! does not read the marker (plan 22, 2026-11-16).
//!
//! The same keys and values, with Cadex's choices on top:
//! - the brief, as upstream, only when the marker asks for it
//!   (`[briefing] inject_on_session_start`, or `inject_on_subagent_start` on
//!   `/brief`); the client sends no `briefing=1` since plan 35 B (the
//!   warning "auto-injected — .ai-memory.toml [briefing]" was a lie without
//!   the file), and Cadex writes the file in every project with it on.
//! - a `workspace` the client sent (the account's, with
//!   memory.shareAcrossAccounts off) outranks the marker's: that setting is the
//!   owner's privacy choice, and a committed file must not undo it.
//! - not sent: the repository identity and `aliases` (Cadex names a project
//!   by its main repository root, server-side), home routes and server
//!   profiles.

#[cfg(test)]
use std::path::Path;

use crate::marker;

/// The query with the marker's pairs; `None` when nothing changes.
pub(crate) fn amend(path: &str, query: &str) -> Option<String> {
    if !matches!(path, "/hook" | "/handoff" | "/brief") {
        return None;
    }
    let mut pairs: Vec<(String, String)> = serde_urlencoded::from_str(query).ok()?;
    let cwd = pairs.iter().find(|(k, _)| k == "cwd").map(|(_, v)| v.clone())?;
    let home = marker::home_dir();
    let found = settings_marker(&cwd, home.as_deref())?;
    let text = std::fs::read_to_string(&found).ok()?;
    apply(&mut pairs, path, &text);
    serde_urlencoded::to_string(&pairs).ok()
}

/// The marker for `cwd`, as upstream finds it; else, in a worktree, the main checkout's (plan 35,
/// 2026-11-19): the file Cadex makes sits in the main checkout and a worktree in a sibling folder
/// (a Cadex task, the bkdg-space) sees it only once it is committed, or never when the owner keeps
/// it "only on this Mac", and with the brief coming only from the marker such a session started
/// with none. A divergence from upstream, which counts on the commit. A worktree's own file wins.
pub(crate) fn settings_marker(cwd: &str, home: Option<&std::path::Path>) -> Option<std::path::PathBuf> {
    if let Some(found) = marker::find_settings_marker(cwd, home) {
        return Some(found);
    }
    // Read from the `.git` files (project_key.rs), never git2: opening the repository with libgit2
    // on every hook took the tool hook from 0.7 to 3.0 ms (make perf, 2026-11-20).
    let main = crate::project_key::main_root(std::path::Path::new(cwd));
    let main = main.to_str()?;
    marker::find_settings_marker(main, home).filter(|found| found.parent().is_some_and(|dir| dir == std::path::Path::new(main)))
}

fn set(pairs: &mut Vec<(String, String)>, key: &str, value: String) {
    pairs.retain(|(k, _)| k != key);
    pairs.push((key.to_string(), value));
}

fn has(pairs: &[(String, String)], key: &str) -> bool {
    pairs.iter().any(|(k, v)| k == key && !v.is_empty())
}

/// A `[profile]` flag as upstream forwards it: `0` when falsy, else `1`.
fn profile_flag(text: &str, key: &str) -> String {
    let off = marker::parse_flag_in(text, key).is_some_and(|v| marker::is_falsy(&v));
    if off { "0" } else { "1" }.to_string()
}

pub(crate) fn apply(pairs: &mut Vec<(String, String)>, path: &str, text: &str) {
    if let Some(workspace) = marker::parse_key_in(text, "workspace")
        && !has(pairs, "workspace")
    {
        set(pairs, "workspace", workspace);
    }
    if let Some(strategy) = marker::parse_key_in(text, "project_strategy") {
        set(pairs, "project_strategy", strategy);
    }
    if let Some(project) = marker::parse_key_in(text, "project") {
        set(pairs, "project", project);
        set(pairs, "project_src", "marker".into());
    }
    if let Some(drop) = marker::parse_key_in(text, "drop_subagent_captures").filter(|v| !v.is_empty()) {
        set(pairs, "drop_subagent", drop);
    }
    if let Some(global) = marker::parse_flag_in(text, "default_global") {
        set(pairs, "default_global", global);
    }
    let brief_key = if path == "/brief" { "inject_on_subagent_start" } else { "inject_on_session_start" };
    if let Some(briefing) = marker::parse_flag_in(text, brief_key) {
        set(pairs, "briefing", briefing);
    }
    if let Some(budget) = marker::parse_flag_in(text, "max_chars") {
        set(pairs, "briefing_budget", budget);
    }
    set(pairs, "profile_contribute", profile_flag(text, "contribute"));
    set(pairs, "profile_consume", profile_flag(text, "consume"));
    // `[retrieval]` (v3.5.0, upstream #2038): sent empty when the key is
    // absent, so removing it clears what the project stored. The server
    // checks the range. Cadex's engine has no reranker, so a
    // `min_relevance` makes every `memory_query` of the project fail
    // (upstream's rule); the app does not offer it (plan 35 F, 2026-11-19).
    for key in ["default_result_limit", "min_relevance"] {
        set(pairs, key, marker::parse_flag_in(text, key).unwrap_or_default());
    }
    let off = |v: Option<String>| v.is_some_and(|v| marker::is_falsy(&v));
    if off(marker::parse_scoped_flag_in(text, "recovery", "deliver_on_session_start", true)) {
        set(pairs, "handoff", "0".into());
    }
    if off(marker::parse_scoped_flag_in(text, "recovery", "deliver_on_session_start", false)) {
        set(pairs, "recovery", "0".into());
    }
}

/// Whether `dir` has a marker of its own (tests).
#[cfg(test)]
fn marker_in(dir: &Path) -> bool {
    dir.join(marker::MARKER_FILENAME).is_file()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pairs(query: &str) -> Vec<(String, String)> {
        serde_urlencoded::from_str(query).unwrap()
    }

    fn get<'a>(pairs: &'a [(String, String)], key: &str) -> Option<&'a str> {
        pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
    }

    #[test]
    fn the_marker_names_the_project_and_turns_the_brief_off() {
        let mut p = pairs("event=session-start&cwd=%2Fr&project_strategy=repo-root&briefing=1");
        let text = "workspace = \"team\"\nproject = \"app\"\n[briefing]\ninject_on_session_start = false # off\nmax_chars = 4000\n";
        apply(&mut p, "/handoff", text);
        assert_eq!(get(&p, "workspace"), Some("team"));
        assert_eq!(get(&p, "project"), Some("app"));
        assert_eq!(get(&p, "project_src"), Some("marker"));
        assert_eq!(get(&p, "briefing"), Some("false"));
        assert_eq!(get(&p, "briefing_budget"), Some("4000"));
        assert_eq!(get(&p, "profile_contribute"), Some("1"));
        assert_eq!(get(&p, "handoff"), None);
    }

    #[test]
    fn the_account_workspace_wins_and_delivery_opt_outs_are_separate() {
        let mut p = pairs("cwd=%2Fr&workspace=acct-1&briefing=1");
        let text = "workspace = \"team\"\n[handoff]\ndeliver_on_session_start = false\n[profile]\nconsume = no\n";
        apply(&mut p, "/handoff", text);
        assert_eq!(get(&p, "workspace"), Some("acct-1"));
        assert_eq!(get(&p, "briefing"), Some("1"), "no briefing key leaves what the query had");
        assert_eq!(get(&p, "handoff"), Some("0"));
        assert_eq!(get(&p, "recovery"), None);
        assert_eq!(get(&p, "profile_consume"), Some("0"));
        let mut r = pairs("cwd=%2Fr");
        apply(&mut r, "/brief", "[recovery]\ndeliver_on_session_start = 0\n[briefing]\ninject_on_subagent_start = true\n");
        assert_eq!((get(&r, "recovery"), get(&r, "handoff"), get(&r, "briefing")), (Some("0"), None, Some("true")));
    }

    #[test]
    fn the_retrieval_keys_are_sent_as_written_and_empty_when_absent() {
        let mut p = pairs("cwd=%2Fr");
        apply(&mut p, "/handoff", "[retrieval]\ndefault_result_limit = 25\nmin_relevance = 0.35\n");
        assert_eq!(get(&p, "default_result_limit"), Some("25"));
        assert_eq!(get(&p, "min_relevance"), Some("0.35"));
        let mut q = pairs("cwd=%2Fr");
        apply(&mut q, "/handoff", "project = \"app\"\n");
        assert_eq!((get(&q, "default_result_limit"), get(&q, "min_relevance")), (Some(""), Some("")));
        // A `[retrieval]`-only marker is a settings boundary (upstream's marker.rs).
        let home = tempfile::tempdir().unwrap();
        let sub = home.path().join("repo/pkg");
        std::fs::create_dir_all(&sub).unwrap();
        std::fs::write(home.path().join("repo/.ai-memory.toml"), "project = \"outer\"\n").unwrap();
        std::fs::write(sub.join(".ai-memory.toml"), "[retrieval]\nmin_relevance = 0.4\n").unwrap();
        let found = marker::find_settings_marker(sub.to_str().unwrap(), Some(home.path())).unwrap();
        assert_eq!(found, sub.join(".ai-memory.toml"));
    }

    #[test]
    fn a_sibling_worktree_reads_the_main_checkouts_marker_until_it_has_its_own() {
        let tmp = tempfile::tempdir().unwrap();
        let tmp = tmp.path().canonicalize().unwrap();
        let main = tmp.join("center");
        std::fs::create_dir_all(&main).unwrap();
        let git = |dir: &std::path::Path, args: &[&str]| {
            assert!(std::process::Command::new("git").args(args).current_dir(dir).output().unwrap().status.success(), "git {args:?}");
        };
        git(&main, &["init", "-q"]);
        git(&main, &["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "first"]);
        git(&main, &["worktree", "add", "-q", tmp.join("space").to_str().unwrap()]);
        let space = tmp.join("space");
        assert!(settings_marker(space.to_str().unwrap(), Some(&tmp)).is_none(), "no marker anywhere");
        std::fs::write(main.join(".ai-memory.toml"), "project = \"center\"\n[briefing]\ninject_on_session_start = true\n").unwrap();
        assert_eq!(settings_marker(space.to_str().unwrap(), Some(&tmp)), Some(main.join(".ai-memory.toml")), "the main checkout's, uncommitted");
        std::fs::write(space.join(".ai-memory.toml"), "project = \"space\"\n").unwrap();
        assert_eq!(settings_marker(space.to_str().unwrap(), Some(&tmp)), Some(space.join(".ai-memory.toml")), "its own wins");
    }

    #[test]
    fn a_capture_only_marker_is_transparent_and_home_bounds_the_walk() {
        let home = tempfile::tempdir().unwrap();
        let repo = home.path().join("repo");
        let sub = repo.join("pkg");
        std::fs::create_dir_all(&sub).unwrap();
        std::fs::write(repo.join(".ai-memory.toml"), "project = \"outer\"\n").unwrap();
        std::fs::write(sub.join(".ai-memory.toml"), "[capture]\nignore_paths = [\"*.env\"]\n").unwrap();
        assert!(marker_in(&sub));
        let found = marker::find_settings_marker(sub.to_str().unwrap(), Some(home.path())).unwrap();
        assert_eq!(found, repo.join(".ai-memory.toml"));
        let nearest = marker::find_marker(sub.to_str().unwrap(), Some(home.path())).unwrap();
        assert_eq!(nearest, sub.join(".ai-memory.toml"));
        let config = marker::read_capture_config(&nearest).unwrap();
        assert_eq!(config.ignore_paths, vec!["*.env".to_string()]);
        std::fs::write(sub.join(".ai-memory.toml"), "[capture]\nother = 1\n").unwrap();
        assert!(marker::read_capture_config(&nearest).is_err(), "unknown key fails closed");
        let elsewhere = tempfile::tempdir().unwrap();
        assert!(marker::find_settings_marker(elsewhere.path().to_str().unwrap(), Some(home.path())).is_none());
    }
}
