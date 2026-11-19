//! Plan 40 A2 (docs/plans/40-memory-panel.md): the fake memory folder every
//! panel test and screenshot uses. Built only through upstream's own writes
//! (Store's writer, Wiki::write_page, send_agent_message, the workstream and
//! auto-improve stages), the way ai-memory-web's own suite seeds its fixtures
//! (tests/suite/routes.rs, operations.rs, workstreams.rs, pending.rs at the
//! pinned commit), so the folder is one upstream itself could have written.
//!
//! Same content on every run: fixed session ids and fixed `occurred_at` for
//! sessions and observations. What upstream stamps with "now" and offers no
//! override for (page versions, session ends, messages, runs, proposals)
//! varies, so tests compare counts and order, never those times.
//!
//! Shared by tests/panel_parity.rs and examples/panel_seed.rs.

#![allow(dead_code)]

use std::path::Path;

use ai_memory_core::{
    ActorContext, AgentKind, NewHandoff, NewObservation, NewSession, NewSessionUsage,
    ObservationKind, PagePath, ProjectId, Sanitized, Sanitizer, SessionId, Tier, WorkspaceId,
};
use ai_memory_core::ObservationKind as K;
use ai_memory_store::Store;

// A sibling file, by path: examples/panel_seed.rs includes this one by path too.
#[path = "seed_queues.rs"]
mod queues;
use queues::{seed_inbox, seed_proposals, seed_workstream};
use ai_memory_wiki::{Wiki, WritePageRequest};

pub const WORKSPACE: &str = "default";
/// The busy project: four sessions (one open), pages with history, links,
/// rules and slots, the handoff, the inbox, the workstream, two proposals.
pub const MAIN: &str = "cadex";
/// A second project: one session, a page linking into MAIN, one proposal.
pub const SITE: &str = "site";
/// Upstream's reserved cross-project scope: one page, no sessions.
pub const GLOBAL: &str = "_global";
/// A project with nothing in it.
pub const EMPTY: &str = "empty";

/// 2026-11-01T12:00:00Z in microseconds, the store's time unit.
pub const T0_MICROS: i64 = 1_793_534_400_000_000;
const MINUTE: i64 = 60_000_000;

/// The sessions, by fixed id (upstream keeps a UUID native id as is).
pub const S_DONE: &str = "00000000-0000-4000-8000-000000000001";
pub const S_SHORT: &str = "00000000-0000-4000-8000-000000000002";
pub const S_OPEN: &str = "00000000-0000-4000-8000-000000000003";
pub const S_CODEX: &str = "00000000-0000-4000-8000-000000000004";
pub const S_SITE: &str = "00000000-0000-4000-8000-000000000005";

/// The page written twice, for the history and its diff.
pub const VERSIONED_PAGE: &str = "decisions/engine.md";
pub const VERSIONED_PAGE_TITLE: &str = "Engine process";
pub const WORKSTREAM_NAME: &str = "panel rewrite";
pub const HANDOFF_SUMMARY: &str = "Seed handoff: the panel screens are next";

/// What the seed holds, per project, as upstream counts it.
pub struct ProjectCounts {
    pub name: &'static str,
    pub sessions: u64,
    pub observations: u64,
    pub pages: u64,
    pub open_sessions: u64,
    pub pending_inbox: u64,
    pub pending_proposals: u64,
}

pub const PROJECTS: [ProjectCounts; 4] = [
    ProjectCounts { name: MAIN, sessions: 4, observations: 15, pages: 5, open_sessions: 1, pending_inbox: 2, pending_proposals: 2 },
    ProjectCounts { name: SITE, sessions: 1, observations: 2, pages: 1, open_sessions: 0, pending_inbox: 0, pending_proposals: 1 },
    ProjectCounts { name: GLOBAL, sessions: 0, observations: 0, pages: 1, open_sessions: 0, pending_inbox: 0, pending_proposals: 0 },
    ProjectCounts { name: EMPTY, sessions: 0, observations: 0, pages: 0, open_sessions: 0, pending_inbox: 0, pending_proposals: 0 },
];

/// Versions of VERSIONED_PAGE.
pub const VERSIONS: u64 = 2;
/// Messages to MAIN: two waiting, one an agent already collected.
pub const MESSAGES_SENT: u64 = 3;

pub fn session_id(raw: &str) -> SessionId {
    SessionId::from_native(raw)
}

/// Write the whole seed into `dir` (empty or missing) and close the store.
pub async fn seed(dir: &Path) -> anyhow::Result<()> {
    std::fs::create_dir_all(dir)?;
    let store = Store::open(dir)?;
    let wiki = Wiki::new(dir, store.writer.clone())?;
    let ws = store.writer.get_or_create_workspace(WORKSPACE).await?;
    let main = store.writer.get_or_create_project(ws, MAIN, None).await?;
    let site = store.writer.get_or_create_project(ws, SITE, None).await?;
    let global = store.writer.get_or_create_project(ws, GLOBAL, None).await?;
    store.writer.get_or_create_project(ws, EMPTY, None).await?;

    seed_sessions(&store, ws, main, site).await?;
    seed_pages(&wiki, ws, main, site, global).await?;
    seed_handoff(&store, ws, main).await?;
    seed_inbox(&store, &wiki, ws, main, site).await?;
    seed_workstream(&store, ws, main).await?;
    seed_proposals(&store, ws, main, &["proposals/retry-policy.md", "proposals/socket-mode.md"]).await?;
    seed_proposals(&store, ws, site, &["proposals/deploy.md"]).await?;
    drop(wiki);
    // Drains the writer and checkpoints the WAL into the main file.
    store.close().await;
    Ok(())
}

/// One session: begin at `start` minutes after T0, one observation a minute,
/// ended unless `open`, with token usage when given.
struct SessionSpec<'a> {
    id: &'a str,
    agent: AgentKind,
    start: i64,
    rows: &'a [(ObservationKind, &'a str)],
    open: bool,
    usage: Option<(u64, u64, u64, u64)>,
}

async fn seed_sessions(store: &Store, ws: WorkspaceId, main: ProjectId, site: ProjectId) -> anyhow::Result<()> {
    let done = [
        (K::SessionStart, "Session started"),
        (K::UserPrompt, "Plan the memory panel"),
        (K::PreToolUse, "Read docs/plans/40-memory-panel.md"),
        (K::PostToolUse, "Read docs/plans/40-memory-panel.md"),
        (K::Stop, "Answered with the phases"),
        (K::SessionEnd, "Session ended"),
    ];
    let short = [
        (K::SessionStart, "Session started"),
        (K::UserPrompt, "Why does the socket refuse me"),
        (K::Notification, "Waiting for permission"),
        (K::SessionEnd, "Session ended"),
    ];
    let open = [
        (K::SessionStart, "Session started"),
        (K::UserPrompt, "Write the seed"),
        (K::PreCompact, "Context compacted"),
    ];
    let codex = [(K::SessionStart, "Session started"), (K::Other, "Codex ran the tests")];
    let site_rows = [(K::SessionStart, "Session started"), (K::UserPrompt, "Deploy the site")];
    let specs = [
        (main, SessionSpec { id: S_DONE, agent: AgentKind::ClaudeCode, start: 0, rows: &done, open: false, usage: Some((12_000, 3_400, 500, 80_000)) }),
        (main, SessionSpec { id: S_SHORT, agent: AgentKind::ClaudeCode, start: 60, rows: &short, open: false, usage: Some((2_000, 600, 0, 9_000)) }),
        (main, SessionSpec { id: S_OPEN, agent: AgentKind::ClaudeCode, start: 120, rows: &open, open: true, usage: None }),
        (main, SessionSpec { id: S_CODEX, agent: AgentKind::Codex, start: 180, rows: &codex, open: false, usage: None }),
        (site, SessionSpec { id: S_SITE, agent: AgentKind::ClaudeCode, start: 240, rows: &site_rows, open: false, usage: Some((1_000, 200, 0, 0)) }),
    ];
    for (project, spec) in specs {
        seed_session(store, ws, project, spec).await?;
    }
    Ok(())
}

async fn seed_session(store: &Store, ws: WorkspaceId, project: ProjectId, spec: SessionSpec<'_>) -> anyhow::Result<()> {
    let id = session_id(spec.id);
    let at = T0_MICROS + spec.start * MINUTE;
    store.writer.begin_session(NewSession {
        id,
        workspace_id: ws,
        project_id: project,
        agent_kind: spec.agent,
        cwd: Some(format!("/seed/{}", spec.id).into()),
        actor_user: None,
        occurred_at: Some(at),
        origin: None,
    }).await?;
    for (n, (kind, title)) in spec.rows.iter().enumerate() {
        let obs = NewObservation {
            occurred_at: Some(at + (n as i64 + 1) * MINUTE),
            session_id: id,
            workspace_id: ws,
            project_id: project,
            kind: *kind,
            extension: None,
            source_event: None,
            title: (*title).to_owned(),
            body: format!("{title} (seed observation {n})"),
            importance: 5,
            file_path: None,
        };
        store.writer.insert_observation(Sanitized::new(obs, &Sanitizer::builtin())).await?;
    }
    if !spec.open {
        store.writer.end_session(id, None).await?;
    }
    if let Some((input, output, cache_write, cache_read)) = spec.usage {
        store.writer.upsert_session_usage(NewSessionUsage {
            session_id: id,
            input_tokens: input,
            output_tokens: output,
            cache_write_tokens: cache_write,
            cache_read_tokens: cache_read,
            model: Some("claude-seed-1".into()),
        }).await?;
    }
    Ok(())
}

fn page(ws: WorkspaceId, project: ProjectId, path: &str, kind: &str, body: &str) -> WritePageRequest {
    WritePageRequest {
        workspace_id: ws,
        project_id: project,
        path: PagePath::new(path).expect("seed page path"),
        frontmatter: serde_json::json!({"kind": kind}),
        body: body.to_owned(),
        tier: Tier::Semantic,
        pinned: false,
        title: None,
        admission_ctx: None,
        author_id: None,
        actor: ActorContext::anonymous(),
        evidence: Vec::new(),
    }
}

/// Link targets go first: a link resolves against the pages that exist.
async fn seed_pages(wiki: &Wiki, ws: WorkspaceId, main: ProjectId, site: ProjectId, global: ProjectId) -> anyhow::Result<()> {
    let first = format!("# {VERSIONED_PAGE_TITLE}\n\nThe engine runs in its own process.\n");
    let second = format!("# {VERSIONED_PAGE_TITLE}\n\nThe engine runs in its own process, one per memory folder.\n\nIt listens on a Unix socket.\n");
    let pages = [
        page(ws, main, VERSIONED_PAGE, "decision", &first),
        page(ws, main, VERSIONED_PAGE, "decision", &second),
        page(ws, main, "gotchas/socket.md", "gotcha", "# Socket mode\n\nThe socket is 0600; see [[decisions/engine.md]].\n"),
        page(ws, main, "_rules/commit-style.md", "rule", "# Commit style\n\nOne topic per commit, message in English.\n"),
        page(ws, main, "_slots/current-focus.md", "fact", "# Current focus\n\nThe memory panel, plan 40.\n"),
        page(ws, main, "index.md", "fact", "# Cadex memory\n\n- [[decisions/engine.md]]\n- [[gotchas/socket.md]]\n"),
        page(ws, site, "deploy.md", "fact", "# Deploy\n\nThe site follows [[cadex:decisions/engine.md]].\n"),
        page(ws, global, "_rules/language.md", "rule", "# Language\n\nCode in English, docs in Portuguese.\n"),
    ];
    for req in pages {
        wiki.write_page(req).await?;
    }
    Ok(())
}

async fn seed_handoff(store: &Store, ws: WorkspaceId, main: ProjectId) -> anyhow::Result<()> {
    store.writer.insert_handoff(NewHandoff {
        workspace_id: ws,
        project_id: main,
        from_session_id: Some(session_id(S_DONE)),
        from_agent: AgentKind::ClaudeCode,
        to_agent: None,
        cwd: Some(format!("/seed/{S_DONE}").into()),
        summary: HANDOFF_SUMMARY.into(),
        open_questions: vec!["Which screen first?".into()],
        next_steps: vec!["Build the overview".into()],
        files_touched: vec![VERSIONED_PAGE.into()],
        owner_user: None,
    }).await?;
    Ok(())
}
