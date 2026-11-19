//! An off project out of the memory tools (plan 35 I: "a busca de outros
//! projetos não o enxerga"), on `/mcp`, without touching upstream's server:
//!
//! - a call naming an off project (`project`, or a `scopes` entry with it)
//!   is answered here, as a tool error, and never reaches upstream;
//! - in an answer, every list item that carries an off project's name
//!   (`project_name`, as the cross-project `global_hits` do, or `project`)
//!   is taken out, in the result and in the JSON its text holds.
//!
//! Projects are matched by name, the only thing upstream's answers carry: a
//! project on elsewhere with the same name as an off one is hidden too.
//! Nothing runs while no project is off.

use std::path::Path;

use axum::body::{Body, Bytes};
use axum::extract::Request;
use axum::http::{StatusCode, header};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use serde_json::Value;

/// Upstream's own cap on a request body (engine.rs); answers get more room.
const MAX_BODY: usize = 10 * 1024 * 1024;
const MAX_ANSWER: usize = 64 * 1024 * 1024;

fn names_off(value: Option<&Value>, off: &[String]) -> bool {
    value.and_then(Value::as_str).is_some_and(|name| off.iter().any(|o| o == name))
}

/// Whether a `tools/call` names an off project.
pub(crate) fn asks_for_off(message: &Value, off: &[String]) -> bool {
    if message.get("method").and_then(Value::as_str) != Some("tools/call") {
        return false;
    }
    let Some(args) = message.pointer("/params/arguments") else { return false };
    names_off(args.get("project"), off)
        || args.get("scopes").and_then(Value::as_array).is_some_and(|s| s.iter().any(|e| names_off(e.get("project"), off)))
}

fn item_is_off(item: &Value, off: &[String]) -> bool {
    names_off(item.get("project_name"), off) || names_off(item.get("project"), off)
}

/// Takes the off projects' items out of `value`, in place; true when any went.
pub(crate) fn strip(value: &mut Value, off: &[String]) -> bool {
    match value {
        Value::Array(items) => {
            let before = items.len();
            items.retain(|item| !item_is_off(item, off));
            let mut changed = items.len() != before;
            for item in items.iter_mut() {
                changed |= strip(item, off);
            }
            changed
        }
        Value::Object(map) => {
            let mut changed = false;
            for (key, inner) in map.iter_mut() {
                if key == "text"
                    && let Some(text) = inner.as_str()
                    && let Ok(mut parsed) = serde_json::from_str::<Value>(text)
                    && strip(&mut parsed, off)
                {
                    *inner = Value::String(parsed.to_string());
                    changed = true;
                } else {
                    changed |= strip(inner, off);
                }
            }
            changed
        }
        _ => false,
    }
}

fn refused(id: Value) -> Response {
    let body = serde_json::json!({"jsonrpc": "2.0", "id": id, "result": {
        "content": [{"type": "text", "text": "This project's memory is off on this Mac."}], "isError": true,
    }});
    ([(header::CONTENT_TYPE, "application/json")], body.to_string()).into_response()
}

/// The `/mcp` half of the off gate (off.rs).
pub(crate) async fn filter(data_dir: &Path, req: Request, next: Next) -> Response {
    let off = crate::off::current(data_dir);
    if off.names.is_empty() {
        return next.run(req).await;
    }
    let (parts, body) = req.into_parts();
    let Ok(bytes) = axum::body::to_bytes(body, MAX_BODY).await else {
        return StatusCode::PAYLOAD_TOO_LARGE.into_response();
    };
    if let Ok(message) = serde_json::from_slice::<Value>(&bytes)
        && asks_for_off(&message, &off.names)
    {
        return refused(message.get("id").cloned().unwrap_or(Value::Null));
    }
    let response = next.run(Request::from_parts(parts, Body::from(bytes))).await;
    let (mut parts, body) = response.into_parts();
    let Ok(bytes) = axum::body::to_bytes(body, MAX_ANSWER).await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    let Ok(mut answer) = serde_json::from_slice::<Value>(&bytes) else {
        return Response::from_parts(parts, Body::from(bytes));
    };
    if !strip(&mut answer, &off.names) {
        return Response::from_parts(parts, Body::from(bytes));
    }
    parts.headers.remove(header::CONTENT_LENGTH);
    Response::from_parts(parts, Body::from(Bytes::from(answer.to_string())))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn off() -> Vec<String> {
        vec!["secret".into()]
    }

    #[test]
    fn a_call_naming_an_off_project_is_refused() {
        let call = |args: Value| serde_json::json!({"method": "tools/call", "params": {"name": "memory_query", "arguments": args}});
        assert!(asks_for_off(&call(serde_json::json!({"query": "x", "project": "secret"})), &off()));
        assert!(asks_for_off(&call(serde_json::json!({"scopes": [{"workspace": "default", "project": "secret"}]})), &off()));
        assert!(!asks_for_off(&call(serde_json::json!({"query": "x", "global": true})), &off()));
        assert!(!asks_for_off(&serde_json::json!({"method": "tools/list"}), &off()));
    }

    #[test]
    fn global_hits_of_an_off_project_leave_the_answer_and_its_text() {
        let inner = serde_json::json!({"hits": [], "global_hits": [
            {"workspace_name": "default", "project_name": "secret", "title": "keys"},
            {"workspace_name": "default", "project_name": "acme", "title": "cache"},
        ]});
        let mut answer = serde_json::json!({"jsonrpc": "2.0", "id": 1, "result": {
            "content": [{"type": "text", "text": inner.to_string()}], "structuredContent": inner,
        }});
        assert!(strip(&mut answer, &off()));
        let text: Value = serde_json::from_str(answer.pointer("/result/content/0/text").unwrap().as_str().unwrap()).unwrap();
        assert_eq!(text["global_hits"].as_array().unwrap().len(), 1);
        assert_eq!(text["global_hits"][0]["project_name"], "acme");
        assert_eq!(answer.pointer("/result/structuredContent/global_hits").unwrap().as_array().unwrap().len(), 1);
        let mut plain = serde_json::json!({"result": {"content": [{"type": "text", "text": "no json here"}]}});
        assert!(!strip(&mut plain, &off()), "nothing to take, nothing changed");
    }
}
