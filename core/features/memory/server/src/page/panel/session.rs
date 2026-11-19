//! What upstream shows of a session's retrievals and of a page's evidence
//! only in its HTML (plan 40 B), under
//! `extra/workspaces/{workspace}/projects/{project}/`:
//!
//! - `sessions/{session_id}/retrievals?offset&limit` (ai-memory-web's
//!   routes/retrievals.rs): the session must exist (404 otherwise), then
//!   `retrieval_history_page`, 25 by default, at most 200 →
//!   `{"total","offset","limit","records":[{"id","created_at","query",
//!   "scope_kind","source","result_limit","min_relevance","filters",
//!   "duration_us","result_count","notice","hits":[{"position","page_path",
//!   "page_version","relevance","explanation"}]}]}`.
//! - `evidence/{*path}?evidence_offset` (routes/page.rs and knowledge.rs):
//!   the page's metadata as `page_meta` has it, which `/api/v1/.../pages/{path}`
//!   leaves out (`author`, `expires_at`, `expired`; the rest repeats it),
//!   and the "evidence and validity" box (`page_provenance`, 20 sources a
//!   page) → `{"meta":{…},"evidence":{"version","sources":[{"kind",
//!   "created_at","session_id","observation_id"}],"source_count",
//!   "disagreements":[{"page":{…},"outgoing"}],"disagreement_count","offset"}}`.
//!   The "why was this page retrieved" fold needs a search query and stays
//!   with the search screen.

use std::sync::Arc;

use ai_memory_core::{ActorContext, OwnerFilter, SessionId};
use axum::Json;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::super::{Params, error};
use super::{OWNER, PanelCtx, bad, internal, micros, number, scope};

const RETRIEVALS_SHOWN: usize = 25;
const RETRIEVALS_MAX: usize = 200;

pub(crate) async fn retrievals(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project, raw)): Path<(String, String, String)>,
    axum::extract::Query(q): Params,
) -> Response {
    let Ok(session_id) = raw.parse::<SessionId>() else { return bad("invalid session id") };
    let (offset, limit) = match (number(&q, "offset"), number(&q, "limit")) {
        (Ok(o), Ok(l)) => (o.unwrap_or(0), l.unwrap_or(RETRIEVALS_SHOWN).clamp(1, RETRIEVALS_MAX)),
        (Err(r), _) | (_, Err(r)) => return r,
    };
    let s = match scope(&ctx, &workspace, &project).await {
        Ok(s) => s,
        Err(r) => return r,
    };
    let reader = &ctx.page.reader;
    match reader.session_summary_scoped(s.workspace_id, s.project_id, session_id, OWNER).await {
        Ok(Some(_)) => {}
        Ok(None) => return error(StatusCode::NOT_FOUND, "no such session in the project"),
        Err(e) => return internal(e),
    }
    let to_i64 = |n: usize| i64::try_from(n).unwrap_or(i64::MAX);
    let page = match reader.retrieval_history_page(s.workspace_id, s.project_id, session_id, to_i64(offset), to_i64(limit)).await {
        Ok(page) => page,
        Err(e) => return internal(e),
    };
    let records: Vec<Value> = page
        .records
        .into_iter()
        .map(|r| {
            let hits: Vec<Value> = r
                .hits
                .into_iter()
                .map(|h| json!({
                    "position": h.position, "page_path": h.page_path, "page_version": h.page_version,
                    "relevance": h.relevance, "explanation": h.explanation,
                }))
                .collect();
            json!({
                "id": r.id, "created_at": r.created_at.to_string(), "query": r.query, "scope_kind": r.scope_kind,
                "source": r.source, "result_limit": r.result_limit, "min_relevance": r.min_relevance,
                "filters": r.filters, "duration_us": r.duration_us, "result_count": r.result_count,
                "notice": r.notice, "hits": hits,
            })
        })
        .collect();
    Json(json!({"total": page.total, "offset": offset, "limit": limit, "records": records})).into_response()
}

pub(crate) async fn evidence(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project, path)): Path<(String, String, String)>,
    axum::extract::Query(q): Params,
) -> Response {
    let offset = match number(&q, "evidence_offset") {
        Ok(o) => o.unwrap_or(0),
        Err(r) => return r,
    };
    if let Err(r) = scope(&ctx, &workspace, &project).await {
        return r;
    }
    let reader = &ctx.page.reader;
    let meta = match reader.page_meta(&workspace, &project, &path).await {
        Ok(Some(meta)) => meta,
        Ok(None) => return error(StatusCode::NOT_FOUND, "no such page"),
        Err(e) => return internal(e),
    };
    // The page view's filter is the request's actor (upstream's
    // `owner_filter_for`), which the owner's requests leave anonymous.
    let owner = OwnerFilter::for_actor_context(&ActorContext::anonymous());
    let found = reader.page_provenance(meta.workspace_id, meta.project_id, meta.path.clone(), None, owner, offset).await;
    let p = match found {
        Ok(Some(p)) => p,
        Ok(None) => return error(StatusCode::NOT_FOUND, "no such page"),
        Err(e) => return internal(e),
    };
    let sources: Vec<Value> = p
        .sources
        .into_iter()
        .map(|s| json!({
            "kind": s.kind, "created_at": micros(s.created_at),
            "session_id": s.session_id.map(|id| id.to_string()), "observation_id": s.observation_id,
        }))
        .collect();
    let disagreements: Vec<Value> =
        p.disagreements.into_iter().map(|d| json!({"page": d.page, "outgoing": d.outgoing})).collect();
    Json(json!({
        "meta": meta,
        "evidence": {
            "version": p.page_id.to_string(),
            "sources": sources,
            "source_count": p.source_count,
            "disagreements": disagreements,
            "disagreement_count": p.disagreement_count,
            "offset": offset,
        },
    }))
    .into_response()
}
