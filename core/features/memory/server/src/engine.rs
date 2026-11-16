//! Store, wiki, embedder, hook router and MCP service, wired the way
//! `ai-memory serve` wires them (crates/ai-memory-cli/src/commands/serve.rs),
//! minus TCP, web, auth and LLM providers.

use std::future::IntoFuture;
use std::os::unix::fs::PermissionsExt;
use std::sync::Arc;
use std::time::{Duration, Instant};

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
use tracing::info;

use crate::Args;
use crate::lazy_embedder::LazyLocalEmbedder;

/// Same cap as upstream serve's `MAX_BODY_BYTES`.
const MAX_BODY_BYTES: usize = 10 * 1024 * 1024;

/// Build the embedder stack upstream serve builds for `local`: the model
/// behind the capacity gate that keeps one slot for queries.
fn local_embedder(args: &Args) -> Arc<dyn Embedder> {
    let lazy: Arc<dyn Embedder> = Arc::new(LazyLocalEmbedder::new(
        args.data_dir.join("models"),
        args.embed_idle,
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

fn hook_state(
    store: &Store,
    wiki: &Wiki,
    ids: (ai_memory_core::WorkspaceId, ai_memory_core::ProjectId),
    active_project: &ActiveProject,
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
        profile_notify: None,
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
        record_tool_names: false,
        index_file_paths: false,
        skip_wiki_checkpoints: false,
    }
}

/// Bind the socket, replacing a stale file, readable only by the owner.
fn bind_socket(path: &std::path::Path) -> Result<tokio::net::UnixListener> {
    if path.exists() {
        std::fs::remove_file(path).with_context(|| format!("removing stale {}", path.display()))?;
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let listener = tokio::net::UnixListener::bind(path)
        .with_context(|| format!("binding {}", path.display()))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    Ok(listener)
}

async fn shutdown_signal(cancel: CancellationToken) {
    use tokio::signal::unix::{SignalKind, signal};
    let mut term = signal(SignalKind::terminate()).expect("SIGTERM handler");
    let mut int = signal(SignalKind::interrupt()).expect("SIGINT handler");
    tokio::select! {
        _ = term.recv() => {}
        _ = int.recv() => {}
    }
    info!("shutdown signal received");
    cancel.cancel();
}

/// Run the engine until SIGTERM/SIGINT.
pub async fn run(args: Args, started: Instant) -> Result<()> {
    std::fs::create_dir_all(&args.data_dir)?;
    let embedder = args.embeddings.then(|| local_embedder(&args));
    let (store, wiki) = open_wiki(&args, embedder.clone()).await?;
    let ws = store
        .writer
        .get_or_create_workspace(ai_memory_core::DEFAULT_WORKSPACE_NAME)
        .await?;
    let proj = store
        .writer
        .get_or_create_project(ws, ai_memory_core::DEFAULT_PROJECT_NAME, None)
        .await?;
    let _watcher = if args.watcher {
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
    if let Some(e) = embedder {
        server = server.with_embedder(e);
    }

    let cancel = CancellationToken::new();
    let mcp_service = StreamableHttpService::new(
        move || Ok(server.clone()),
        LocalSessionManager::default().into(),
        StreamableHttpServerConfig::default()
            .with_cancellation_token(cancel.child_token())
            .with_allowed_hosts(["localhost", "127.0.0.1", "::1"])
            .with_legacy_session_mode(false)
            .with_json_response(true),
    );
    let hooks = hook_router(hook_state(&store, &wiki, (ws, proj), &active_project));
    let workstreams = workstream_router(WorkstreamState {
        writer: store.writer.clone(),
        reader: store.reader.clone(),
        sanitizer: Sanitizer::builtin(),
        wiki: wiki.clone(),
        data_dir: args.data_dir.clone(),
        home_dir: std::env::var("HOME").ok(),
        trusted_proxy_identity: false,
    });
    // Auth disabled: `require_bearer` with no expected token stamps every
    // request as the anonymous actor, which the tools and hooks expect.
    let auth = Arc::new(AuthState::new(None));
    let router = axum::Router::new()
        .nest_service("/mcp", mcp_service)
        .merge(hooks)
        .merge(workstreams)
        .route("/healthz", axum::routing::get(|| async { "ok" }))
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .layer(axum::middleware::from_fn_with_state(auth, require_bearer));

    let listener = bind_socket(&args.socket)?;
    info!(
        socket = %args.socket.display(),
        ready_ms = started.elapsed().as_millis() as u64,
        "cadex-memory ready"
    );
    let shutdown = cancel.clone();
    tokio::spawn(shutdown_signal(cancel.clone()));
    let served = axum::serve(listener, router.into_make_service())
        .with_graceful_shutdown(async move { shutdown.cancelled().await })
        .into_future();
    let result = tokio::select! {
        r = served => r.map_err(anyhow::Error::from),
        () = async { cancel.cancelled().await; tokio::time::sleep(Duration::from_secs(5)).await } => Ok(()),
    };
    let _ = tokio::time::timeout(Duration::from_secs(5), store.close()).await;
    let _ = std::fs::remove_file(&args.socket);
    result
}
