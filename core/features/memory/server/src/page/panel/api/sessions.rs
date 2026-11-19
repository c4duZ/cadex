//! A project's sessions and one session's observations, as upstream's
//! `/api/v1` answers them (ai-memory-web's routes/api.rs at 411d90d:
//! `sessions_handler`, `session_observations_handler`, `cap_body`), the same
//! reads, limits and JSON, with root's session filter (every owner).

use std::sync::Arc;

use ai_memory_core::{ObservationKind, SessionId};
use ai_memory_store::{ObservationOrder, ObservationPage, ObservationRecord, SessionSummary};
use axum::Json;
use axum::extract::{Path, Query, State};
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};

use super::{bad_request, internal, lookup, not_found};
use crate::page::panel::{OWNER, PanelCtx};

const SESSION_LIST_MAX_LIMIT: usize = 100;
const OBSERVATIONS_MAX_LIMIT: usize = 200;
const DEFAULT_BODY_CHARS: usize = 4_000;
const MIN_BODY_CHARS: usize = 200;
const MAX_BODY_CHARS: usize = 16_384;

fn default_session_limit() -> usize {
    20
}

fn default_observation_limit() -> usize {
    50
}

#[derive(Deserialize)]
pub(super) struct SessionListQuery {
    #[serde(default = "default_session_limit")]
    limit: usize,
    #[serde(default)]
    offset: usize,
    #[serde(default)]
    include_open: bool,
}

#[derive(Deserialize)]
pub(super) struct ObservationsQuery {
    #[serde(default = "default_observation_limit")]
    limit: usize,
    #[serde(default)]
    offset: usize,
    #[serde(default)]
    order: Option<String>,
    #[serde(default)]
    kinds: Option<String>,
    #[serde(default)]
    q: Option<String>,
    #[serde(default)]
    body_max_chars: Option<usize>,
}

#[derive(Serialize)]
struct ApiSessionList {
    sessions: Vec<SessionSummary>,
}

#[derive(Serialize)]
struct ApiSessionObservations {
    session: SessionSummary,
    observations: Vec<ObservationRecord>,
    total: u64,
    offset: usize,
    limit: usize,
    order: ObservationOrder,
    elided_other_scope: u64,
    body_max_chars: usize,
}

/// Upstream's `cap_body`: the first `max_chars` and a note of the rest.
fn cap_body(body: &str, max_chars: usize) -> String {
    let total = body.chars().count();
    if total <= max_chars {
        return body.to_owned();
    }
    let mut out: String = body.chars().take(max_chars).collect();
    out.push_str(&format!("\n[body truncated; {} chars omitted]", total - max_chars));
    out
}

pub(super) async fn list(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project)): Path<(String, String)>,
    Query(q): Query<SessionListQuery>,
) -> Response {
    let (ws, proj) = match lookup(&ctx, &workspace, &project).await {
        Ok(ids) => ids,
        Err(r) => return r,
    };
    let limit = q.limit.clamp(1, SESSION_LIST_MAX_LIMIT);
    match ctx.page.reader.sessions_for_scope(ws, proj, OWNER, q.include_open, limit, q.offset).await {
        Ok(sessions) => Json(ApiSessionList { sessions }).into_response(),
        Err(e) => internal(e),
    }
}

fn order(raw: Option<&str>) -> Result<ObservationOrder, Response> {
    match raw.map(str::trim) {
        None | Some("") => Ok(ObservationOrder::Asc),
        Some(r) if r.eq_ignore_ascii_case("asc") => Ok(ObservationOrder::Asc),
        Some(r) if r.eq_ignore_ascii_case("desc") => Ok(ObservationOrder::Desc),
        Some(r) => Err(bad_request(&format!("unknown order: {r} (expected asc or desc)"))),
    }
}

fn kinds(raw: Option<&str>) -> Result<Option<Vec<ObservationKind>>, Response> {
    let mut out = Vec::new();
    for kind in raw.unwrap_or_default().split(',').map(str::trim).filter(|k| !k.is_empty()) {
        match kind.parse::<ObservationKind>() {
            Ok(parsed) => out.push(parsed),
            Err(_) => return Err(bad_request(&format!("unknown observation kind: {kind}"))),
        }
    }
    Ok((!out.is_empty()).then_some(out))
}

pub(super) async fn observations(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project, raw)): Path<(String, String, String)>,
    Query(q): Query<ObservationsQuery>,
) -> Response {
    let (ws, proj) = match lookup(&ctx, &workspace, &project).await {
        Ok(ids) => ids,
        Err(r) => return r,
    };
    let Ok(session_id) = raw.parse::<SessionId>() else {
        return bad_request(&format!("invalid session id: {raw}"));
    };
    let limit = q.limit.clamp(1, OBSERVATIONS_MAX_LIMIT);
    let body_max_chars = q.body_max_chars.unwrap_or(DEFAULT_BODY_CHARS).clamp(MIN_BODY_CHARS, MAX_BODY_CHARS);
    let (order, kinds) = match (order(q.order.as_deref()), kinds(q.kinds.as_deref())) {
        (Ok(o), Ok(k)) => (o, k),
        (Err(r), _) | (_, Err(r)) => return r,
    };
    let reader = &ctx.page.reader;
    let session = match reader.session_summary_scoped(ws, proj, session_id, OWNER).await {
        Ok(Some(s)) => s,
        Ok(None) => return not_found(&format!("session '{session_id}' not found")),
        Err(e) => return internal(e),
    };
    let page = ObservationPage { limit, offset: q.offset, order, kinds, query: q.q.clone() };
    let page = match reader.session_observations_scoped(ws, proj, session_id, page).await {
        Ok(page) => page,
        Err(e) => return internal(e),
    };
    let observations = page
        .records
        .into_iter()
        .map(|mut record| {
            record.body = cap_body(&record.body, body_max_chars);
            record
        })
        .collect();
    Json(ApiSessionObservations {
        session,
        observations,
        total: page.total,
        offset: q.offset,
        limit,
        order,
        elided_other_scope: page.elided_other_scope,
        body_max_chars,
    })
    .into_response()
}
