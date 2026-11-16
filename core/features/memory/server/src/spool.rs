//! The hook queue: what `cadex memory-hook` could not deliver because the
//! engine was down (core/features/memory/hook_client.zig) is replayed here at
//! start, in the order it was written. Each file is one request:
//!
//! ```json
//! {"v":1,"path":"/hook?event=post-tool-use&agent=claude-code&...","body":"<hook JSON as text>"}
//! ```
//!
//! named `<unix ms, 13 digits>-<random hex>.json`, so sorting by name is
//! sorting by time. The client writes it to a `.tmp` name and renames it, so
//! a half-written file is never read here.
//!
//! The requests go through the router in process, past the token check:
//! the client checked the token before queueing, and the token file may be
//! gone by now (the session closed).

use std::path::{Path, PathBuf};

use axum::Router;
use axum::body::Body;
use axum::http::{Request, header};
use tower::ServiceExt;

/// One queued request.
#[derive(Debug, PartialEq)]
pub(crate) struct Queued {
    pub(crate) path: String,
    pub(crate) body: String,
}

/// Parse one spool file. Only `/hook` requests are queued.
pub(crate) fn parse(text: &str) -> Option<Queued> {
    let value: serde_json::Value = serde_json::from_str(text).ok()?;
    let path = value.get("path")?.as_str()?;
    if !path.starts_with("/hook?") && !path.starts_with("/hook/") {
        return None;
    }
    let body = match value.get("body") {
        Some(serde_json::Value::String(s)) => s.clone(),
        _ => String::new(),
    };
    Some(Queued { path: path.to_string(), body })
}

/// The queued files, oldest first.
fn queued_files(dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut files: Vec<PathBuf> = entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "json"))
        .collect();
    files.sort();
    files
}

enum Outcome {
    Delivered,
    /// The engine refused it (4xx): retrying would refuse it again.
    Refused(u16),
    /// The engine failed (5xx): keep it for the next start.
    Failed(u16),
}

async fn replay(router: &Router, queued: Queued) -> Outcome {
    let request = Request::post(&queued.path)
        .header(header::HOST, "localhost")
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(queued.body));
    let Ok(request) = request else { return Outcome::Refused(400) };
    match router.clone().oneshot(request).await {
        Ok(response) if response.status().is_success() => Outcome::Delivered,
        Ok(response) if response.status().is_client_error() => Outcome::Refused(response.status().as_u16()),
        Ok(response) => Outcome::Failed(response.status().as_u16()),
        Err(never) => match never {},
    }
}

/// Replay every queued request; returns how many were delivered.
///
/// A delivered file is deleted. A refused one (malformed, or a 4xx) is
/// renamed `.rejected` and kept for a person to read, but not replayed again.
/// On a 5xx the drain stops and keeps the rest, in order, for the next start.
pub(crate) async fn drain(router: Router, dir: PathBuf) -> usize {
    let mut delivered = 0;
    for file in queued_files(&dir) {
        let Some(queued) = std::fs::read_to_string(&file).ok().as_deref().and_then(parse) else {
            tracing::warn!(file = %file.display(), "spool file unreadable; set aside");
            let _ = std::fs::rename(&file, file.with_extension("rejected"));
            continue;
        };
        match replay(&router, queued).await {
            Outcome::Delivered => {
                let _ = std::fs::remove_file(&file);
                delivered += 1;
            }
            Outcome::Refused(status) => {
                tracing::warn!(file = %file.display(), status, "spooled event refused; set aside");
                let _ = std::fs::rename(&file, file.with_extension("rejected"));
            }
            Outcome::Failed(status) => {
                tracing::warn!(file = %file.display(), status, "spooled event failed; kept for the next start");
                break;
            }
        }
    }
    if delivered > 0 {
        tracing::info!(delivered, "spooled hook events replayed");
    }
    delivered
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_spool_file_names_a_hook_request_and_its_body() {
        let got = parse(r#"{"v":1,"path":"/hook?event=stop&agent=claude-code","body":"{\"a\":1}"}"#);
        assert_eq!(got, Some(Queued { path: "/hook?event=stop&agent=claude-code".into(), body: "{\"a\":1}".into() }));
        assert_eq!(parse(r#"{"path":"/mcp","body":""}"#), None, "only hook requests are queued");
        assert_eq!(parse("not json"), None);
        assert_eq!(parse(r#"{"path":"/hook?event=stop"}"#).unwrap().body, "");
    }

    #[tokio::test]
    async fn the_drain_keeps_order_deletes_what_lands_and_sets_aside_what_is_refused() {
        use axum::routing::post;
        let dir = tempfile::tempdir().unwrap();
        let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let log = seen.clone();
        let router = Router::new().route(
            "/hook",
            post(move |q: axum::extract::RawQuery| async move {
                let q = q.0.unwrap_or_default();
                log.lock().unwrap().push(q.clone());
                if q.contains("bad") { axum::http::StatusCode::BAD_REQUEST } else { axum::http::StatusCode::OK }
            }),
        );
        let write = |name: &str, q: &str| {
            std::fs::write(dir.path().join(name), format!(r#"{{"v":1,"path":"/hook?{q}","body":"{{}}"}}"#)).unwrap();
        };
        write("0000000000002-b.json", "event=two");
        write("0000000000001-a.json", "event=one");
        write("0000000000003-c.json", "event=bad");
        std::fs::write(dir.path().join("0000000000004-d.json.tmp"), "half").unwrap();
        assert_eq!(drain(router, dir.path().to_path_buf()).await, 2);
        assert_eq!(*seen.lock().unwrap(), vec!["event=one", "event=two", "event=bad"]);
        let mut left: Vec<String> = std::fs::read_dir(dir.path()).unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap()).collect();
        left.sort();
        assert_eq!(left, vec!["0000000000003-c.rejected", "0000000000004-d.json.tmp"]);
    }
}
