//! `cadex-memory scan-transcripts`: find a project's Claude Code sessions
//! across several account folders (each a `CLAUDE_CONFIG_DIR`).
//!
//! Upstream backfill (`ai-memory-cli/src/commands/backfill.rs`) reads one
//! store: the process's own `CLAUDE_CONFIG_DIR`, or `~/.claude`. The
//! workstream crate already takes the store as a parameter
//! (`session_dir`), so several roots only need a loop here and a dedup by
//! session id. Importing what is found (map each event to a `/hook/batch`
//! item) is the part of upstream backfill that still lives in the cli crate.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use ai_memory_workstream::{ManagedHarness, export_transcript, list_native_sessions};
use anyhow::{Context, Result};

/// Same per-harness cap upstream backfill uses (`PER_HARNESS_SCAN_LIMIT`).
const SCAN_LIMIT: usize = 200;

/// One session found under one account folder.
pub(crate) struct FoundSession {
    pub(crate) root: PathBuf,
    pub(crate) native_session_id: String,
    pub(crate) events: usize,
}

/// Sessions recorded for `cwd` under every root, newest first per root.
pub(crate) async fn scan(home: &Path, cwd: &Path, roots: &[PathBuf]) -> Result<Vec<FoundSession>> {
    let mut seen = HashSet::new();
    let mut found = Vec::new();
    for root in roots {
        let projects = root.join("projects");
        let sessions =
            list_native_sessions(ManagedHarness::Claude, home, cwd, Some(&projects), SCAN_LIMIT)
                .await
                .with_context(|| format!("listing {}", projects.display()))?;
        for session in sessions {
            if !seen.insert(session.native_session_id.clone()) {
                continue;
            }
            let exported = export_transcript(
                ManagedHarness::Claude,
                home,
                cwd,
                Some(&projects),
                &session.native_session_id,
                None,
            )
            .await?;
            found.push(FoundSession {
                root: root.clone(),
                native_session_id: session.native_session_id,
                events: exported.events.len(),
            });
        }
    }
    Ok(found)
}

/// Entry point for the subcommand: `--cwd <dir> --claude-dir <dir>...`.
pub(crate) fn run(args: &[String]) -> Result<()> {
    let mut cwd = None;
    let mut roots = Vec::new();
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--cwd" => cwd = it.next().map(PathBuf::from),
            "--claude-dir" => roots.extend(it.next().map(PathBuf::from)),
            other => anyhow::bail!("unknown argument {other}"),
        }
    }
    let cwd = cwd.context("--cwd is required")?;
    let home = PathBuf::from(std::env::var("HOME").context("HOME")?);
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build()?;
    let found = runtime.block_on(scan(&home, &cwd, &roots))?;
    for s in &found {
        println!("{}\t{}\t{} events", s.root.display(), s.native_session_id, s.events);
    }
    println!("{} sessions from {} roots", found.len(), roots.len());
    Ok(())
}
