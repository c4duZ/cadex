//! The Saúde screen's fixes (plan 40 G): what upstream's health checks tell
//! the operator to run (ai-memory-core's fix_lines at 411d90d), done by this
//! engine when the owner presses the fix, since Cadex has no `ai-memory`
//! command. `POST extra/fix`, `{"what": …}`:
//!
//! - `"spool"` for `ai-memory recover`'s spool part: the queue
//!   `cadex memory-hook` left is sent again now, as on every start
//!   (crate::spool::drain) → `{"delivered","pending"}`. The run journal
//!   part is `cadex continue`'s: the next run replays it (run/recover.rs).
//! - `"embed"` for `ai-memory embed`: vectors for the latest pages that have
//!   none under the local model, every project, through upstream's
//!   `run_embedding_backfill`, as its `/admin/embed` handler calls it.
//! - `"embed-all"` for `ai-memory embed --force`: the vectors made under
//!   another model or dimension deleted and every page embedded again, as
//!   that handler's all-projects branch does, for every workspace.
//!   Both → `{"embedded","skipped","failed"}`; without the local model,
//!   upstream's 503 "embedder not configured on server".
//! - `"compact"` for `ai-memory compact --confirm`: the store rebuilt and
//!   vacuumed (`WriterHandle::compact`, upstream's `/admin/compact`), which
//!   blocks writes while it runs; the app asks before →
//!   `{"bytes_before","bytes_after","bytes_reclaimed"}`.

use std::collections::HashSet;
use std::sync::Arc;

use ai_memory_consolidate::{EmbedBackfillOptions, run_embedding_backfill};
use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Deserialize;
use serde_json::json;

use super::super::error;
use super::{PanelCtx, bad, internal};

#[derive(Deserialize)]
pub(crate) struct Fix {
    what: String,
}

pub(crate) async fn handle(State(ctx): State<Arc<PanelCtx>>, Json(fix): Json<Fix>) -> Response {
    match fix.what.as_str() {
        "spool" => spool(&ctx).await,
        "embed" => embed(&ctx, false).await,
        "embed-all" => embed(&ctx, true).await,
        "compact" => match ctx.page.writer.compact().await {
            Ok(s) => Json(json!({"bytes_before": s.bytes_before, "bytes_after": s.bytes_after, "bytes_reclaimed": s.bytes_reclaimed()}))
                .into_response(),
            Err(e) => internal(e),
        },
        _ => bad("what is spool, embed, embed-all or compact"),
    }
}

async fn spool(ctx: &PanelCtx) -> Response {
    let router = match ctx.page.inner() {
        Ok(router) => router,
        Err(r) => return r,
    };
    let dir = ctx.sources.spool_dir.clone();
    let delivered = crate::spool::drain(router, dir.clone()).await;
    let pending = tokio::task::spawn_blocking(move || crate::spool::health(&dir).0).await.unwrap_or(0);
    Json(json!({"delivered": delivered, "pending": pending})).into_response()
}

async fn embed(ctx: &PanelCtx, reembed: bool) -> Response {
    let (Some(embedder), Some((provider, model, dim))) = (ctx.sources.model.clone(), ctx.sources.identity()) else {
        return error(StatusCode::SERVICE_UNAVAILABLE, "embedder not configured on server");
    };
    let page = &ctx.page;
    let scopes = match page.reader.list_all_scopes().await {
        Ok(scopes) => scopes,
        Err(e) => return internal(e),
    };
    if reembed {
        let workspaces: HashSet<_> = scopes.iter().map(|s| s.workspace_id).collect();
        for ws in workspaces {
            if let Err(e) = page.writer.delete_stale_page_embeddings(ws, None, provider.clone(), model.clone(), dim).await {
                return internal(e);
            }
        }
    }
    let (mut embedded, mut skipped, mut failed) = (0usize, 0usize, 0usize);
    for scope in scopes {
        let options = EmbedBackfillOptions { reembed, dry_run: false };
        match run_embedding_backfill(&page.reader, &page.writer, &page.wiki, &embedder, scope.workspace_id, scope.project_id, options).await {
            Ok(counts) => {
                embedded += counts.embedded;
                skipped += counts.skipped;
                failed += counts.failed;
            }
            Err(e) => return internal(e),
        }
    }
    Json(json!({"embedded": embedded, "skipped": skipped, "failed": failed})).into_response()
}
