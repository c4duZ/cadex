//! `GET extra/health` (plan 40 B): upstream's server health page
//! (ai-memory-web's routes/health.rs) fed by this engine, the local server
//! on the owner's Mac (the owner's decision, 2026-11-19: "a Saúde com os
//! contadores do engine local"). The same store reads (`derived_index_status`
//! for the configured embedder, `storage_status`,
//! `session_consolidation_queue`) and upstream's own checks (health_checks.rs,
//! a copy, in English, its fix lines included) over a snapshot whose process
//! side is ours:
//!
//! - hooks: the hook router's `IngestMetrics` since the engine started (a
//!   restart after the model unloads starts them again, as a restart of
//!   upstream's server does);
//! - the write queue: the store writer's depth;
//! - the spool: the queue `cadex memory-hook` leaves (crate::spool::health),
//!   with no retries nor cap (the hook keeps neither);
//! - the journal: `cadex-memory run`'s recovery journal (run/journal.rs);
//! - providers: none. Cadex calls no remote provider (ADR 0028), so the
//!   LLM and embedding provider lines and their checks drop out; the local
//!   model's state is `model` instead (off, absent, downloading, ready,
//!   loaded, as the Memory page names it).
//!
//! → `{"checks":[{"id","status","detail","fix"}],"hooks":{…IngestMetricsSnapshot},
//! "write_queue":{"queued","capacity"},"spool":{"pending","oldest_age_ms"},
//! "journal":{"pending","degraded","finish_failed","unreadable"},
//! "consolidation":{…},"derived":{…},"storage":{…}|null,
//! "embedder":{"provider","model","dim"}|null,"model":state,"reranker":false}`.

use std::sync::Arc;

use axum::Json;
use axum::extract::State;
use axum::response::{IntoResponse, Response};
use serde_json::json;

use super::health_checks::{HealthSnapshot, JournalState, ProcessState, SpoolState, checks};
use super::{PanelCtx, internal};

/// The process side, off the async workers: the spool and the journal
/// touch the disk, as upstream's probe runs in `spawn_blocking`.
async fn process(ctx: &Arc<PanelCtx>) -> ProcessState {
    let spool_dir = ctx.sources.spool_dir.clone();
    let run_dir = ctx.page.data_dir.join("run");
    let write_queue = Some(ctx.page.writer.queue_depth());
    let disk = tokio::task::spawn_blocking(move || {
        let (pending, oldest_age_ms) = crate::spool::health(&spool_dir);
        let journal = match crate::run::journal_summary(&run_dir) {
            Ok((pending, degraded, finish_failed)) => JournalState { pending, degraded, finish_failed, unreadable: false },
            Err(_) => JournalState { unreadable: true, ..JournalState::default() },
        };
        (SpoolState { pending, oldest_age_ms, retries_total: 0, capacity: 0 }, journal)
    })
    .await;
    let (spool, journal) = disk.unwrap_or_default();
    ProcessState { write_queue, spool: Some(spool), journal: Some(journal) }
}

pub(crate) async fn handle(State(ctx): State<Arc<PanelCtx>>) -> Response {
    let reader = &ctx.page.reader;
    let embedder = ctx.sources.identity();
    let derived = match &embedder {
        Some(identity) => reader.derived_index_status_for_embedding(identity.clone()).await,
        None => reader.derived_index_status().await,
    };
    let derived = match derived {
        Ok(d) => d,
        Err(e) => return internal(e),
    };
    // As upstream: a failed pragma read keeps the page up with no figures.
    let storage = reader.storage_status().await.ok();
    let consolidation = match reader.session_consolidation_queue().await {
        Ok(q) => q,
        Err(e) => return internal(e),
    };
    let process = process(&ctx).await;
    let snapshot = HealthSnapshot {
        ingest: ctx.sources.ingest.snapshot(),
        process,
        derived,
        storage,
        consolidation,
        embedder,
    };
    let found: Vec<_> = checks(&snapshot)
        .into_iter()
        .map(|c| json!({"id": c.id, "status": c.status.label(), "detail": c.detail, "fix": c.fix}))
        .collect();
    let spool = process.spool.unwrap_or_default();
    let journal = process.journal.unwrap_or_default();
    let (queued, capacity) = process.write_queue.unwrap_or_default();
    Json(json!({
        "checks": found,
        "hooks": snapshot.ingest,
        "write_queue": {"queued": queued, "capacity": capacity},
        "spool": {"pending": spool.pending, "oldest_age_ms": spool.oldest_age_ms},
        "journal": {
            "pending": journal.pending, "degraded": journal.degraded,
            "finish_failed": journal.finish_failed, "unreadable": journal.unreadable,
        },
        "consolidation": snapshot.consolidation,
        "derived": snapshot.derived,
        "storage": snapshot.storage,
        "embedder": snapshot.embedder.as_ref().map(|(provider, model, dim)| json!({"provider": provider, "model": model, "dim": dim})),
        "model": super::super::overview::model_state(&ctx.page),
        "reranker": false,
    }))
    .into_response()
}
