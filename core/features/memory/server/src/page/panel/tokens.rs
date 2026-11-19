//! Token usage (plan 40 B): the "Uso de tokens" panel upstream draws on the
//! project's tokens tab and on a session's page (ai-memory-web's
//! operations.rs `usage_panel`, over `token_usage_report_page`), as JSON.
//!
//! - `GET extra/workspaces/{w}/projects/{p}/tokens?calls_*`
//! - `GET extra/workspaces/{w}/projects/{p}/sessions/{session_id}/tokens?calls_*`
//!
//! The filters are upstream's query names and rules (`UsageQuery::store_query`,
//! **copied** from operations.rs at 411d90d, since it is crate-private
//! there): `calls_q` (≤256 chars), `calls_sort=tokens|recent`,
//! `calls_signal=all|signals`, `calls_offset` (50 a page), `calls_model`,
//! `calls_agent` (a wire name), `calls_session`, `calls_from`/`calls_until`
//! (UTC, `YYYY-MM-DD`, `…THH:MM`, `…THH:MM:SS` or RFC 3339), `calls_turn`,
//! `calls_tool`.
//!
//! → `{"call_count","matching_calls","matching_tokens","input","output",
//! "cache_read","cache_write","offset","calls":[{"call_id","session_id",
//! "agent","model","input","output","cache_read","cache_write","total",
//! "observed_at","response_at","turn_id","response_id","tools":[…],"signal"}]}`;
//! `signal` is upstream's flag: `above-average` (over 3× the mean, from 5
//! calls on), `large-context` (≥100k tokens in), `long-output` (≥20k out)
//! or null.

use std::collections::HashMap;
use std::sync::Arc;

use ai_memory_core::{AgentKind, SessionId};
use ai_memory_store::{TokenCallOrder, TokenCallQuery, TokenUsageReport};
use axum::Json;
use axum::extract::{Path, State};
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::super::Params;
use super::{OWNER, PanelCtx, bad, internal, scope};

/// Upstream's `usage_time`: a UTC date or time to microseconds.
fn usage_time(value: &str) -> Result<Option<i64>, Response> {
    if value.is_empty() {
        return Ok(None);
    }
    if value.len() > 64 {
        return Err(bad("time too long"));
    }
    let normalized = match value.len() {
        10 => format!("{value}T00:00:00Z"),
        16 => format!("{value}:00Z"),
        19 => format!("{value}Z"),
        _ => value.into(),
    };
    normalized.parse::<jiff::Timestamp>().map(|t| Some(t.as_microsecond())).map_err(|_| bad("unreadable time"))
}

/// Upstream's `UsageQuery::store_query`, from the request's pairs.
fn store_query(q: &HashMap<String, String>) -> Result<TokenCallQuery, Response> {
    let get = |k: &str| q.get(k).map(String::as_str).unwrap_or("");
    let order = match get("calls_sort") {
        "" | "tokens" => TokenCallOrder::Largest,
        "recent" => TokenCallOrder::Recent,
        _ => return Err(bad("calls_sort must be tokens or recent")),
    };
    let signals_only = match get("calls_signal") {
        "" | "all" => false,
        "signals" => true,
        _ => return Err(bad("calls_signal must be all or signals")),
    };
    let search = get("calls_q");
    if search.chars().count() > 256 {
        return Err(bad("calls_q too long"));
    }
    let agent = match get("calls_agent") {
        "" => None,
        raw => Some(AgentKind::ALL.into_iter().find(|a| a.as_str() == raw).ok_or_else(|| bad("unknown agent"))?),
    };
    let session_id = match get("calls_session") {
        "" => None,
        raw => Some(raw.parse::<SessionId>().map_err(|_| bad("invalid session id"))?),
    };
    let offset = match get("calls_offset") {
        "" => 0,
        raw => raw.parse().map_err(|_| bad("calls_offset must be a whole number"))?,
    };
    let (from_us, until_us) = (usage_time(get("calls_from"))?, usage_time(get("calls_until"))?);
    let (model, turn, tool) = (get("calls_model"), get("calls_turn"), get("calls_tool"));
    if from_us.zip(until_us).is_some_and(|(from, until)| from >= until) || model.len() > 128 || turn.len() > 128 || tool.len() > 128 {
        return Err(bad("invalid token usage filter"));
    }
    let some = |s: &str| (!s.is_empty()).then(|| s.to_owned());
    Ok(TokenCallQuery {
        search: search.trim().into(),
        signals_only,
        order,
        offset,
        model: some(model),
        agent,
        session_id,
        from_us,
        until_us,
        turn_id: some(turn),
        tool: some(tool),
    })
}

fn report_json(report: TokenUsageReport, offset: usize) -> Value {
    let input_total = report.input + report.cache_read + report.cache_write;
    let mean = (input_total + report.output).checked_div(report.call_count).unwrap_or(0);
    let calls: Vec<Value> = report
        .calls
        .into_iter()
        .map(|c| {
            let context = c.input + c.cache_read + c.cache_write;
            let total = context + c.output;
            let signal = if report.call_count >= 5 && total > mean.saturating_mul(3) {
                Some("above-average")
            } else if context >= 100_000 {
                Some("large-context")
            } else if c.output >= 20_000 {
                Some("long-output")
            } else {
                None
            };
            json!({
                "call_id": c.call_id, "session_id": c.session_id, "agent": c.agent, "model": c.model,
                "input": c.input, "output": c.output, "cache_read": c.cache_read, "cache_write": c.cache_write,
                "total": total, "observed_at": c.observed_at, "response_at": c.response_at,
                "turn_id": c.turn_id, "response_id": c.response_id, "tools": c.tools, "signal": signal,
            })
        })
        .collect();
    json!({
        "call_count": report.call_count,
        "matching_calls": report.matching_calls,
        "matching_tokens": report.matching_tokens,
        "input": report.input,
        "output": report.output,
        "cache_read": report.cache_read,
        "cache_write": report.cache_write,
        "offset": offset,
        "calls": calls,
    })
}

async fn report(ctx: &PanelCtx, workspace: &str, project: &str, session: Option<&str>, q: &HashMap<String, String>) -> Response {
    let query = match store_query(q) {
        Ok(query) => query,
        Err(r) => return r,
    };
    let session = match session.map(str::parse::<SessionId>) {
        None => None,
        Some(Ok(id)) => Some(id),
        Some(Err(_)) => return bad("invalid session id"),
    };
    let s = match scope(ctx, workspace, project).await {
        Ok(s) => s,
        Err(r) => return r,
    };
    let offset = query.offset;
    match ctx.page.reader.token_usage_report_page(s.workspace_id, s.project_id, OWNER, session, query).await {
        Ok(r) => Json(report_json(r, offset)).into_response(),
        Err(e) => internal(e),
    }
}

pub(crate) async fn project(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project)): Path<(String, String)>,
    axum::extract::Query(q): Params,
) -> Response {
    report(&ctx, &workspace, &project, None, &q).await
}

pub(crate) async fn session(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project, session_id)): Path<(String, String, String)>,
    axum::extract::Query(q): Params,
) -> Response {
    report(&ctx, &workspace, &project, Some(&session_id), &q).await
}
