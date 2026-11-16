//! The two import jobs (import.rs runs them): a project's history at its
//! first SessionStart, and the sessions that ran outside Cadex at engine start.

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime};

use ai_memory_core::{OwnerFilter, ProjectId, SessionId, WorkspaceId};
use ai_memory_store::ScopeRow;

use crate::accounts;
use crate::import::{BACKFILL_EVENTS, BACKFILL_SESSIONS, Budget, Context, Planned, Report, SessionStarted, import_all};
use crate::import_state::{Backfill, BackfillMarker, Checkpoints};
use crate::project_paths::{ProjectPaths, main_repo_root};
use crate::replay::Target;
use crate::transcripts::{self, Transcript};

/// The hook route answers before it stores the event; the session's row
/// shows up a moment later.
const SESSION_ROW_WAIT: Duration = Duration::from_secs(10);
/// A transcript written this recently may belong to a session still open
/// (its hooks capture it, or the next start imports it).
pub(crate) const LIVE_WINDOW: Duration = Duration::from_secs(120);
/// What one start may import from outside sessions: a catch-up, not a
/// bootstrap (the history import has upstream's larger caps); what is left
/// is imported at the next start (the checkpoint does not move past it).
pub(crate) const OUTSIDE_SESSIONS: usize = 50;
pub(crate) const OUTSIDE_EVENTS: usize = 10_000;

async fn session_scope(ctx: &Context, id: &str) -> Option<(WorkspaceId, ProjectId, Option<String>)> {
    let deadline = Instant::now() + SESSION_ROW_WAIT;
    loop {
        if let Ok(Some(scope)) = ctx.reader.find_session_scope(SessionId::from_native(id)).await {
            return Some(scope);
        }
        if Instant::now() >= deadline || ctx.stop.is_cancelled() {
            return None;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

/// The workspace to name on the replayed events: none for `default`, as
/// the live hook sends none then.
fn workspace_of(row: &ScopeRow) -> Option<String> {
    Some(row.workspace_name.clone()).filter(|w| w != ai_memory_core::DEFAULT_WORKSPACE_NAME)
}

async fn matching(accounts: Vec<PathBuf>, root: PathBuf, after: Option<SystemTime>) -> Vec<Transcript> {
    let until = SystemTime::now();
    tokio::task::spawn_blocking(move || transcripts::matching(&accounts, &ProjectPaths::for_root(&root), after, until))
        .await
        .unwrap_or_default()
}

async fn session_count(ctx: &Context, ws: WorkspaceId, proj: ProjectId) -> u64 {
    let counts = ctx.reader.session_counts_by_agent(ws, proj, OwnerFilter::Any, None).await;
    counts.map(|c| c.iter().map(|a| a.sessions).sum()).unwrap_or(u64::MAX)
}

/// Whether the history import has this project to do (started, or due at
/// the SessionStart just made): then its sessions are the history import's,
/// with its larger caps, not the start's catch-up. Found 2026-11-16 in the
/// end-to-end run: the catch-up, 1.5 s after the SessionStart that started
/// the engine, took the brand-new project's whole history first.
async fn backfill_pending(ctx: &Context, row: &ScopeRow) -> bool {
    match BackfillMarker::new(&ctx.data_dir, &row.workspace_id, &row.project_id).read() {
        Backfill::Done => false,
        Backfill::Started => true,
        Backfill::Never => session_count(ctx, row.workspace_id, row.project_id).await <= 1,
    }
}

/// A project's history, once: when the session that just started is the
/// only one its project has (or an earlier import was cut short), import the
/// newest sessions of its root, subfolders and worktrees from every account
/// that writes to its workspace, the starting session left out.
pub(crate) async fn backfill(ctx: &Context, job: &SessionStarted) {
    let started = Instant::now();
    let Some((ws, proj, session_cwd)) = session_scope(ctx, &job.session_id).await else {
        tracing::debug!(session = %job.session_id, "session not in the store; no history import");
        return;
    };
    let marker = BackfillMarker::new(&ctx.data_dir, &ws, &proj);
    match marker.read() {
        Backfill::Done => return,
        Backfill::Started => {}
        Backfill::Never => {
            if session_count(ctx, ws, proj).await > 1 {
                marker.set(Backfill::Done);
                return;
            }
            marker.set(Backfill::Started);
        }
    }
    let Ok(Some(row)) = ctx.reader.scope_row_by_ids(ws, proj).await else { return };
    let cwd = session_cwd.or_else(|| job.cwd.clone()).unwrap_or_default();
    let root = match &row.repo_path {
        Some(path) => PathBuf::from(path),
        None => main_repo_root(Path::new(&cwd)).unwrap_or_else(|| PathBuf::from(&cwd)),
    };
    if root.as_os_str().is_empty() {
        return;
    }
    let readers = accounts::for_workspace(&ctx.accounts(), Some(&row.workspace_name));
    let mut found = matching(readers, root.clone(), None).await;
    found.retain(|t| t.id != job.session_id);
    found.truncate(BACKFILL_SESSIONS);
    let cwd = row.repo_path.clone().unwrap_or_else(|| root.to_string_lossy().into_owned());
    let target = Target { cwd, workspace: workspace_of(&row) };
    let planned: Vec<Planned<'_>> = found.iter().map(|transcript| Planned { transcript, target: &target }).collect();
    let mut budget = Budget { sessions: BACKFILL_SESSIONS, events: BACKFILL_EVENTS };
    let mut report = Report::default();
    import_all(ctx, &planned, &mut budget, &mut report).await;
    // Over the caps is final, as upstream's; cut short by the engine's exit
    // stays `started` and resumes at the next SessionStart.
    if !ctx.stop.is_cancelled() {
        marker.set(Backfill::Done);
    }
    report.log(&format!("history of {} imported", root.display()), started);
}

/// A known project: its scope row, its folders, and where its events go.
struct Known {
    row: ScopeRow,
    paths: ProjectPaths,
}

/// The projects with a repository path whose history import is behind
/// them, with their folders. Each costs a `git worktree list`, so this runs
/// only when some transcript is new.
async fn known_projects(ctx: &Context, scopes: &[ScopeRow]) -> Vec<Known> {
    let mut rows = Vec::new();
    for row in scopes.iter().filter(|r| r.repo_path.is_some()) {
        if !backfill_pending(ctx, row).await {
            rows.push(row.clone());
        }
    }
    with_paths(rows).await
}

async fn with_paths(scopes: Vec<ScopeRow>) -> Vec<Known> {
    tokio::task::spawn_blocking(move || {
        scopes.into_iter().filter_map(|row| {
            let paths = ProjectPaths::for_root(Path::new(row.repo_path.as_deref()?));
            Some(Known { row, paths })
        }).collect()
    })
    .await
    .unwrap_or_default()
}

/// The project a transcript belongs to, for one account: its own workspace
/// first (memory.shareAcrossAccounts off), then the shared `default`.
fn owner<'a>(known: &'a [Known], account_key: &str, cwd: &Path) -> Option<&'a Known> {
    let in_ws = |ws: &str| known.iter().find(|k| k.row.workspace_name == ws && k.paths.contains(cwd));
    in_ws(account_key).or_else(|| in_ws(ai_memory_core::DEFAULT_WORKSPACE_NAME))
}

/// The sessions of known projects that ran outside Cadex since the last
/// start: in every account, the transcripts modified after the account's
/// checkpoint and before the live window, not in the store yet, newest
/// first, within the start's budget. An account's checkpoint moves only when
/// none of its sessions was left over.
pub(crate) async fn outside(ctx: &Context) {
    let started = Instant::now();
    let Ok(scopes) = ctx.reader.list_all_scopes().await else { return };
    let until = SystemTime::now() - LIVE_WINDOW;
    let mut checkpoints = Checkpoints::load(&ctx.data_dir);
    let accounts = ctx.accounts();
    let mut found = Vec::new();
    for account in &accounts {
        let (dir, after) = (account.clone(), checkpoints.get(account));
        found.extend(tokio::task::spawn_blocking(move || transcripts::list(&dir, after, until)).await.unwrap_or_default());
    }
    transcripts::newest_first_once(&mut found);
    let known = if found.is_empty() { Vec::new() } else { known_projects(ctx, &scopes).await };
    let targets: Vec<Option<Target>> = found.iter().map(|t| {
        let project = owner(&known, &accounts::key(&t.account), &t.cwd)?;
        Some(Target { cwd: project.row.repo_path.clone()?, workspace: workspace_of(&project.row) })
    }).collect();
    let planned: Vec<Planned<'_>> = found.iter().zip(&targets)
        .filter_map(|(transcript, target)| Some(Planned { transcript, target: target.as_ref()? }))
        .collect();
    let mut budget = Budget { sessions: OUTSIDE_SESSIONS, events: OUTSIDE_EVENTS };
    let mut report = Report::default();
    let handled = import_all(ctx, &planned, &mut budget, &mut report).await;
    for account in &accounts {
        let left = planned.iter().zip(&handled).any(|(p, done)| !done && &p.transcript.account == account);
        if !left && !ctx.stop.is_cancelled() {
            checkpoints.set(account, until);
        }
    }
    checkpoints.save();
    report.log("outside sessions imported", started);
}
