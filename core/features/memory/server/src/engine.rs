//! Store, wiki, embedder, hook router and MCP service, wired the way
//! `ai-memory serve` wires them (crates/ai-memory-cli/src/commands/serve.rs),
//! minus TCP, web, multi-user auth and LLM providers. Serving them (socket,
//! session tokens, sessions, restart) is serve.rs.

use std::sync::Arc;

use ai_memory_core::{ActiveProject, Sanitizer};
use ai_memory_hooks::{
    DEFAULT_HOOK_INGEST_MAX_IN_FLIGHT, HookState, ProjectCacheStore, WorkstreamState, hook_router,
    workstream_router,
};
use ai_memory_llm::{Embedder, EmbeddingCapacity, local_capacity};
use ai_memory_mcp::AiMemoryServer;
use ai_memory_mcp::auth::{AuthState, require_bearer};
use ai_memory_store::Store;
use ai_memory_wiki::{WatcherHandle, Wiki, migrations, run_wiki_migrations};
use anyhow::{Context, Result};
use axum::extract::DefaultBodyLimit;
use rmcp::transport::streamable_http_server::{
    StreamableHttpServerConfig, StreamableHttpService, session::local::LocalSessionManager,
};
use tokio_util::sync::CancellationToken;

use crate::args::Args;
use crate::lazy_embedder::LazyLocalEmbedder;
use crate::restart::ModelEvents;

/// Same cap as upstream serve's `MAX_BODY_BYTES`.
const MAX_BODY_BYTES: usize = 10 * 1024 * 1024;

/// Build the embedder stack upstream serve builds for `local`: the model
/// behind the capacity gate that keeps one slot for queries.
fn local_embedder(args: &Args, events: Arc<ModelEvents>) -> Arc<dyn Embedder> {
    let lazy: Arc<dyn Embedder> = Arc::new(LazyLocalEmbedder::new(
        args.data_dir.join("models"),
        args.embed_idle,
        events,
    ));
    let cores = std::thread::available_parallelism().map_or(4, |n| n.get());
    match EmbeddingCapacity::new(lazy.clone(), local_capacity(cores)) {
        Ok(gated) => Arc::new(gated),
        Err(_) => lazy,
    }
}

/// Open the store and the wiki, run migrations, and attach the embedder.
async fn open_wiki(args: &Args, embedder: Option<Arc<dyn Embedder>>) -> Result<(Store, Wiki)> {
    let store = Store::open(&args.data_dir)
        .with_context(|| format!("opening store at {}", args.data_dir.display()))?;
    run_wiki_migrations(
        &store.writer,
        &store.reader,
        &args.data_dir.join("wiki"),
        &migrations::registry(),
    )
    .await
    .context("applying wiki-structure migrations")?;
    let mut wiki = Wiki::new(&args.data_dir, store.writer.clone())?
        .with_sanitizer(Sanitizer::builtin())
        .with_store_reader(store.reader.clone());
    if let Some(e) = embedder {
        wiki = wiki.with_embedder(e);
    }
    if let Err(e) = wiki.backfill_scope_manifests().await {
        tracing::warn!(error = %e, "scope-manifest backfill failed (non-fatal)");
    }
    Ok((store, wiki))
}

/// The store and the wiki opened and migrated, as `build` opens them, with
/// no embedder (the model is not loaded by a warm-up); the wiki is dropped.
pub(crate) async fn open_for_warm_up(args: &Args) -> Result<Store> {
    let (store, _wiki) = open_wiki(args, None).await?;
    Ok(store)
}

fn hook_state(
    store: &Store,
    wiki: &Wiki,
    ids: (ai_memory_core::WorkspaceId, ai_memory_core::ProjectId),
    active_project: &ActiveProject,
    session_ended: Arc<tokio::sync::Notify>,
) -> HookState {
    HookState {
        ingest_metrics: Arc::new(ai_memory_core::IngestMetrics::default()),
        workspace_id: ids.0,
        project_id: ids.1,
        writer: store.writer.clone(),
        reader: store.reader.clone(),
        wiki: wiki.clone(),
        // No LLM: SessionEnd writes the rule-based session page and handoff.
        consolidator: None,
        sanitizer: Sanitizer::builtin(),
        project_cache: Arc::new(tokio::sync::Mutex::new(ProjectCacheStore::default())),
        active_project: active_project.clone(),
        ingest_semaphore: Arc::new(tokio::sync::Semaphore::new(
            DEFAULT_HOOK_INGEST_MAX_IN_FLIGHT,
        )),
        ingest_gates: ai_memory_hooks::IngestGates::default(),
        session_agents: ai_memory_hooks::SessionAgents::default(),
        cwd_probes: ai_memory_hooks::CwdProbes::default(),
        consolidate_on_session_end: false,
        session_consolidation_notify: None,
        // Rung after every SessionEnd; no profile worker runs here, and
        // handoff.rs takes it as "a session end is done" (plan 22, phase C).
        profile_notify: Some(session_ended),
        capture_assistant_enabled: false,
        claim_handoff_on_session_start: true,
        create_handoff_on_session_end: true,
        per_user_slots: false,
        subagent_sessions: Arc::new(tokio::sync::Mutex::new(
            ai_memory_hooks::SubagentSessionSet::default(),
        )),
        ingest_rate: Arc::new(tokio::sync::Mutex::new(
            ai_memory_hooks::IngestRateLimiter::new(0.0, 1.0),
        )),
        home_dir: std::env::var("HOME").ok(),
        trusted_proxy_identity: false,
        mid_session_routing: ai_memory_core::MidSessionRouting::default(),
        profile: ai_memory_core::profile::ProfileSettings::default(),
        ingest_drop_list: ai_memory_hooks::IngestDropList::default(),
        // The handoff lists the tools by name and the files the edit tools
        // named (session_facts.rs). Names only, never arguments; the path is
        // relative to the checkout (file_claim.rs adds it), and a file
        // outside it or one the sanitizer refuses (secrets) is not kept. A
        // few bytes per call, in the local store only (plan 22, phase C,
        // 2026-11-16). The observation body still keeps upstream's excerpt of
        // the tool's response (2,000 bytes; a Claude Write's response holds the
        // file written): kept by the owner's choice after the real test.
        record_tool_names: true,
        index_file_paths: true,
        skip_wiki_checkpoints: false,
    }
}

/// The engine, wired and ready to serve: the store to close at the end, the
/// routes (without the session-token check, which serve.rs puts in front),
/// and what the lazy embedder says about its model.
pub(crate) struct Engine {
    pub(crate) store: Store,
    pub(crate) router: axum::Router,
    pub(crate) model: Option<Arc<ModelEvents>>,
    /// Rung by the hook router after each SessionEnd (handoff.rs).
    pub(crate) session_ended: Arc<tokio::sync::Notify>,
    /// For the maintenance jobs (maintenance.rs, plan 22 phase F).
    pub(crate) wiki: Wiki,
    pub(crate) embedder: Option<Arc<dyn Embedder>>,
    /// Lives as long as the engine; `None` unless `--watcher`.
    pub(crate) _watcher: Option<WatcherHandle>,
}

/// Open the store and the wiki and build the routes, as upstream serve does.
pub(crate) async fn build(args: &Args, cancel: &CancellationToken) -> Result<Engine> {
    let model = args.embeddings.then(|| Arc::new(ModelEvents::default()));
    let embedder = model.as_ref().map(|events| local_embedder(args, events.clone()));
    let (store, wiki) = open_wiki(args, embedder.clone()).await?;
    let ws = store
        .writer
        .get_or_create_workspace(ai_memory_core::DEFAULT_WORKSPACE_NAME)
        .await?;
    let proj = store
        .writer
        .get_or_create_project(ws, ai_memory_core::DEFAULT_PROJECT_NAME, None)
        .await?;
    let watcher = if args.watcher {
        Some(WatcherHandle::start(wiki.clone())?)
    } else {
        None
    };
    let active_project = ActiveProject::with_config(
        ai_memory_core::ActiveProjectMode::default(),
        ai_memory_core::DEFAULT_PER_KEY_TTL,
        ai_memory_core::DEFAULT_MAX_ENTRIES,
    );
    let mut server = AiMemoryServer::new(store.reader.clone(), store.writer.clone(), ws, proj)
        .with_wiki(wiki.clone())
        .with_active_project(active_project.clone())
        .with_sanitizer(Sanitizer::builtin());
    if let Some(e) = embedder.clone() {
        server = server.with_embedder(e);
    }

    let mcp_service = StreamableHttpService::new(
        move || Ok(server.clone()),
        LocalSessionManager::default().into(),
        StreamableHttpServerConfig::default()
            .with_cancellation_token(cancel.child_token())
            .with_allowed_hosts(["localhost", "127.0.0.1", "::1"])
            .with_legacy_session_mode(false)
            .with_json_response(true),
    );
    let session_ended = Arc::new(tokio::sync::Notify::new());
    let hooks = hook_router(hook_state(&store, &wiki, (ws, proj), &active_project, session_ended.clone()));
    let workstreams = workstream_router(WorkstreamState {
        writer: store.writer.clone(),
        reader: store.reader.clone(),
        sanitizer: Sanitizer::builtin(),
        wiki: wiki.clone(),
        data_dir: args.data_dir.clone(),
        home_dir: std::env::var("HOME").ok(),
        trusted_proxy_identity: false,
    });
    // Upstream's multi-user auth stays off: `require_bearer` with no expected
    // token stamps every request as the anonymous actor, which the tools and
    // hooks expect. Who may connect is serve.rs's job (auth.rs).
    let auth = Arc::new(AuthState::new(None));
    let router = axum::Router::new()
        .nest_service("/mcp", mcp_service)
        .merge(hooks)
        .merge(workstreams)
        .route("/healthz", axum::routing::get(|| async { "ok" }))
        // Plan 22 phase F: the consolidation request for the session's own Claude.
        .route("/cadex/consolidate", axum::routing::get(crate::consolidate_prompt::handle))
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .layer(axum::middleware::from_fn_with_state(auth, require_bearer));
    Ok(Engine { store, router, model, session_ended, wiki: wiki.clone(), embedder, _watcher: watcher })
}
