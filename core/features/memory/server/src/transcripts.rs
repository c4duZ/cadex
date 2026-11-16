//! The Claude Code transcripts of several account folders (plan 22, phase C):
//! `<account>/projects/<folder>/<session id>.jsonl`, each session with the
//! cwd its own records name. The folder name is the cwd with every
//! character outside [A-Za-z0-9] as "-", which cannot be read back (a "-"
//! in a folder name and a "/" look the same), so the cwd comes from the file.
//!
//! Upstream's `list_native_sessions` (ai-memory-workstream) matches one exact
//! cwd in one store; the import needs a project's subfolders and worktrees
//! across every account, so the listing is here and the reading of each
//! transcript stays upstream's (`export_transcript`, in import.rs).
//!
//! `cadex-memory scan-transcripts --cwd <dir> [--claude-dirs a:b]` prints
//! what the import would read for the project of `<dir>` (diagnosis, tests).

use std::collections::HashSet;
use std::io::{BufRead, BufReader, Read as _};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use anyhow::{Context, Result};

use crate::accounts;
use crate::project_paths::{ProjectPaths, main_repo_root};

/// Lines read for a header, as upstream's `session_header` (a transcript
/// can open with summary and snapshot records that name no cwd).
const HEADER_LINES: usize = 64;
/// A header line longer than this is not read (upstream caps it too).
const HEADER_LINE_BYTES: usize = 1024 * 1024;

/// One session's transcript under one account folder.
#[derive(Debug, Clone)]
pub(crate) struct Transcript {
    pub(crate) account: PathBuf,
    pub(crate) id: String,
    pub(crate) cwd: PathBuf,
    pub(crate) modified: SystemTime,
}

impl Transcript {
    /// The folder upstream's exporter takes as the store (`session_dir`).
    pub(crate) fn store(&self) -> PathBuf {
        self.account.join("projects")
    }
}

/// The session id and cwd the first records name.
fn header(path: &Path) -> Option<(String, PathBuf)> {
    let mut reader = BufReader::new(std::fs::File::open(path).ok()?);
    let mut line = String::new();
    for _ in 0..HEADER_LINES {
        line.clear();
        let read = (&mut reader).take(HEADER_LINE_BYTES as u64).read_line(&mut line).ok()?;
        if read == 0 || (read == HEADER_LINE_BYTES && !line.ends_with('\n')) {
            return None;
        }
        let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) else { continue };
        let id = value.get("sessionId").and_then(|v| v.as_str());
        let cwd = value.get("cwd").and_then(|v| v.as_str());
        if let (Some(id), Some(cwd)) = (id, cwd) {
            return Some((id.to_string(), PathBuf::from(cwd)));
        }
    }
    None
}

/// The transcripts of one account modified inside `(after, until]`. Only
/// `projects/<folder>/<id>.jsonl`: a subagent's sidechain
/// (`<id>/subagents/agent-*.jsonl`) is part of its session, never one of its
/// own (upstream's `transcript_file`). A file whose name is not its own
/// session id is skipped too.
pub(crate) fn list(account: &Path, after: Option<SystemTime>, until: SystemTime) -> Vec<Transcript> {
    let Ok(folders) = std::fs::read_dir(account.join("projects")) else { return Vec::new() };
    let mut found = Vec::new();
    for folder in folders.flatten() {
        let Ok(files) = std::fs::read_dir(folder.path()) else { continue };
        for file in files.flatten() {
            let path = file.path();
            if path.extension().is_none_or(|x| x != "jsonl") {
                continue;
            }
            let Some(modified) = file.metadata().ok().and_then(|m| m.is_file().then(|| m.modified().ok()).flatten()) else {
                continue;
            };
            if modified > until || after.is_some_and(|a| modified <= a) {
                continue;
            }
            let Some((id, cwd)) = header(&path) else { continue };
            if path.file_stem().and_then(|s| s.to_str()) != Some(id.as_str()) {
                continue;
            }
            found.push(Transcript { account: account.to_path_buf(), id, cwd, modified });
        }
    }
    found
}

/// The sessions of `paths` in `accounts`, one per session id (the newest
/// copy when two accounts hold it), newest first.
pub(crate) fn matching(accounts: &[PathBuf], paths: &ProjectPaths, after: Option<SystemTime>, until: SystemTime) -> Vec<Transcript> {
    let mut all: Vec<Transcript> = accounts
        .iter()
        .flat_map(|a| list(a, after, until))
        .filter(|t| paths.contains(&t.cwd))
        .collect();
    newest_first_once(&mut all);
    all
}

/// Sort newest first and keep the first of each session id.
pub(crate) fn newest_first_once(all: &mut Vec<Transcript>) {
    all.sort_by(|a, b| b.modified.cmp(&a.modified).then_with(|| a.id.cmp(&b.id)));
    let mut seen = HashSet::new();
    all.retain(|t| seen.insert(t.id.clone()));
}

/// `cadex-memory scan-transcripts --cwd <dir> [--claude-dirs a:b]`.
pub(crate) fn run(args: &[String]) -> Result<()> {
    let (mut cwd, mut listed) = (None, None);
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--cwd" => cwd = it.next().map(PathBuf::from),
            "--claude-dirs" => listed = it.next().map(|s| accounts::parse_list(s)),
            other => anyhow::bail!("unknown argument {other}"),
        }
    }
    let cwd = cwd.context("--cwd is required")?;
    let home = PathBuf::from(std::env::var("HOME").context("HOME")?);
    let dirs = accounts::find(&home, listed.as_deref());
    let root = main_repo_root(&cwd).unwrap_or(cwd);
    let paths = ProjectPaths::for_root(&root);
    let found = matching(&dirs, &paths, None, SystemTime::now());
    for t in &found {
        println!("{}\t{}\t{}", t.account.display(), t.id, t.cwd.display());
    }
    println!("{} sessions of {} in {} accounts", found.len(), root.display(), dirs.len());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(account: &Path, folder: &str, id: &str, cwd: &str) -> PathBuf {
        let dir = account.join("projects").join(folder);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(format!("{id}.jsonl"));
        let lines = [
            serde_json::json!({"type": "summary", "summary": "s"}),
            serde_json::json!({"type": "user", "sessionId": id, "cwd": cwd, "message": {"role": "user", "content": "hi"}}),
        ];
        std::fs::write(&path, lines.map(|l| l.to_string()).join("\n") + "\n").unwrap();
        path
    }

    #[test]
    fn the_cwd_comes_from_the_records_and_sidechains_are_not_sessions() {
        let tmp = tempfile::tempdir().unwrap();
        let account = tmp.path().join("acct");
        // The folder name lies about the cwd ("-" for "/" and for "-").
        write(&account, "-x-my-repo", "s1", "/x/my/repo/src");
        let renamed = write(&account, "-x-my-repo", "renamed", "/x/my/repo");
        std::fs::rename(&renamed, renamed.with_file_name("other.jsonl")).unwrap();
        let side = account.join("projects/-x-my-repo/s1/subagents");
        std::fs::create_dir_all(&side).unwrap();
        std::fs::write(side.join("agent-1.jsonl"), r#"{"sessionId":"s1","cwd":"/x/my/repo"}"#).unwrap();
        let found = list(&account, None, SystemTime::now());
        assert_eq!(found.len(), 1);
        assert_eq!((found[0].id.as_str(), found[0].cwd.as_path()), ("s1", Path::new("/x/my/repo/src")));
        assert!(list(&account, Some(SystemTime::now()), SystemTime::now()).is_empty(), "nothing after now");
    }

    #[test]
    fn a_session_in_two_accounts_is_read_once_from_its_newest_copy() {
        let tmp = tempfile::tempdir().unwrap();
        let (one, two) = (tmp.path().join("one"), tmp.path().join("two"));
        let old = write(&one, "f", "s1", "/r");
        std::fs::File::options().write(true).open(&old).unwrap()
            .set_modified(SystemTime::now() - std::time::Duration::from_secs(60)).unwrap();
        write(&two, "f", "s1", "/r");
        write(&two, "f", "s2", "/r/sub");
        write(&two, "f", "s3", "/elsewhere");
        let paths = ProjectPaths::for_root(Path::new("/r"));
        let found = matching(&[one, two.clone()], &paths, None, SystemTime::now());
        let ids: Vec<(&str, &Path)> = found.iter().map(|t| (t.id.as_str(), t.account.as_path())).collect();
        assert_eq!(ids.len(), 2);
        assert!(ids.contains(&("s1", two.as_path())) && ids.iter().any(|(id, _)| *id == "s2"));
    }
}
