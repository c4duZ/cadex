//! The memory agent (ADR 0029, plan 22 phase G, 2026-11-16): upstream's
//! jobs that need a model, run by the owner's own Claude Code (`claude -p`
//! in the project's account), off by default, only on events (never by a
//! clock), one at a time, within a daily budget and a per-call budget, each
//! call written to a cost ledger.
//!
//! - `config.rs`: `<data-dir>/agent.json`, written by the app, read at each job.
//! - `claude_cli.rs` and `provider.rs`: the `LlmProvider` over `claude -p`.
//! - `ledger.rs`: `<data-dir>/agent/ledger.jsonl` and the day's spend.
//! - `queue.rs`: the queue, the worker and what keeps the engine up.
//! - `jobs.rs`: what each kind of job runs (upstream's public functions).
//! - `improve.rs`: auto-improve and experience for one project (**copied**
//!   from upstream's scheduler, which only runs over every project at once).
//! - `dream.rs`: the dream pass and the idle watch that stops it.
//! - `bootstrap.rs`: "Organize History with AI" over the imported sessions.
//! - `routes.rs`: `/cadex/agent/*` and the middleware that turns a live
//!   SessionEnd or PostCompact into a job.

pub(crate) mod bootstrap;
pub(crate) mod claude_cli;
pub(crate) mod config;
pub(crate) mod dream;
pub(crate) mod improve;
pub(crate) mod jobs;
pub(crate) mod ledger;
pub(crate) mod provider;
pub(crate) mod queue;
pub(crate) mod routes;

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ai_memory_core::{ProjectId, WorkspaceId};
use ai_memory_llm::Embedder;
use ai_memory_store::{ReaderPool, WriterHandle};
use ai_memory_wiki::Wiki;
use tokio_util::sync::CancellationToken;

use crate::restart::InFlight;
use crate::sessions::Sessions;

/// How long one `claude -p` may run before it is killed. Upstream's chat
/// providers time out at 300 s (`DEFAULT_REQUEST_TIMEOUT_SECS`); same here.
pub(crate) const CALL_TIMEOUT: Duration = Duration::from_secs(300);

/// What the jobs read, write and wait on.
pub(crate) struct Ctx {
    pub(crate) reader: ReaderPool,
    pub(crate) writer: WriterHandle,
    pub(crate) wiki: Wiki,
    pub(crate) embedder: Option<Arc<dyn Embedder>>,
    /// The engine's default scope, as upstream gives its `Consolidator`.
    pub(crate) default_scope: (WorkspaceId, ProjectId),
    pub(crate) data_dir: PathBuf,
    pub(crate) home: Option<PathBuf>,
    /// `--import-delay-ms`: how long after its event a job waits.
    pub(crate) delay: Duration,
    pub(crate) sessions: Arc<Sessions>,
    pub(crate) in_flight: Arc<InFlight>,
    pub(crate) stop: CancellationToken,
    /// The Mac's idle time (dream.rs); replaceable in tests.
    pub(crate) idle: dream::IdleReader,
    /// How often a running automatic dream reads the idle time.
    pub(crate) idle_poll: Duration,
    /// `claude --version` per executable, read once per engine run.
    versions: Mutex<HashMap<PathBuf, Option<String>>>,
}

impl Ctx {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        stores: (ReaderPool, WriterHandle, Wiki, Option<Arc<dyn Embedder>>),
        default_scope: (WorkspaceId, ProjectId),
        data_dir: PathBuf,
        delay: Duration,
        sessions: Arc<Sessions>,
        in_flight: Arc<InFlight>,
        stop: CancellationToken,
    ) -> Self {
        let (reader, writer, wiki, embedder) = stores;
        let (idle, idle_poll) = dream::idle_source();
        Self {
            reader,
            writer,
            wiki,
            embedder,
            default_scope,
            data_dir,
            home: std::env::var_os("HOME").map(PathBuf::from),
            delay,
            sessions,
            in_flight,
            stop,
            idle,
            idle_poll,
            versions: Mutex::new(HashMap::new()),
        }
    }

    /// The Claude Code version of `exe`, asked once per engine run.
    pub(crate) async fn version_of(&self, exe: &Path, account: Option<&Path>) -> Option<String> {
        if let Some(known) = self.versions.lock().unwrap_or_else(|e| e.into_inner()).get(exe) {
            return known.clone();
        }
        let found = claude_cli::version(exe, account).await;
        self.versions.lock().unwrap_or_else(|e| e.into_inner()).insert(exe.to_path_buf(), found.clone());
        found
    }

    /// The last version read, for the status route.
    pub(crate) fn any_version(&self) -> Option<String> {
        self.versions.lock().unwrap_or_else(|e| e.into_inner()).values().flatten().next().cloned()
    }
}

/// The agent the routes and the middleware talk to.
pub(crate) struct Agent {
    pub(crate) ctx: Arc<Ctx>,
    pub(crate) queue: Arc<queue::Queue>,
}

/// Start the worker; it ends when `ctx.stop` is cancelled.
pub(crate) fn start(ctx: Ctx) -> Arc<Agent> {
    let ctx = Arc::new(ctx);
    let queue = Arc::new(queue::Queue::new());
    tokio::spawn(queue.clone().work(ctx.clone()));
    Arc::new(Agent { ctx, queue })
}

/// The project of a folder: its scope as the hooks name it and its main
/// repository root (for the account).
pub(crate) fn scope_for(cwd: &str, workspace: Option<&str>) -> Option<queue::Scope> {
    let (workspace, project) = crate::mcp_scope::scope_of(cwd, workspace)?;
    let root = crate::project_paths::main_repo_root(Path::new(cwd));
    Some(queue::Scope { workspace, project, root })
}
