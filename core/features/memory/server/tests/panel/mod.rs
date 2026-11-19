//! Plan 40 A2: what the panel tests share. The seed (seed.rs), the HTML
//! readers (html.rs), the byte-for-byte check (snapshot.rs), and upstream's
//! panel mounted the way examples/web_reference.rs mounts it: `/web` and
//! `/api/v1` from `split_web_routers`, every request as the local owner
//! (AuthLevel::Root), since a single-user Cadex has no login.

#![allow(dead_code)]

pub mod html;
pub mod seed;
pub mod snapshot;

use std::path::Path;

use ai_memory_core::AuthLevel;
use ai_memory_store::Store;
use ai_memory_web::{Recall, WebMountSpec, split_web_routers};
use ai_memory_wiki::Wiki;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;

/// Upstream's panel over the folder at `dir`, and the store under it (the
/// caller closes it with `Store::close`, see snapshot.rs).
pub fn mount(dir: &Path) -> (Store, axum::Router) {
    let store = Store::open(dir).expect("open the seed store");
    let wiki = Wiki::new(dir, store.writer.clone()).expect("open the seed wiki");
    let web = split_web_routers(
        true,
        store.reader.clone(),
        wiki,
        WebMountSpec {
            enable_api: true,
            web_ui_dir: None,
            cors_origins: &[],
            web_slug: "/web",
            base_href: "/web/",
            base_path: "",
            trusted_proxy_identity: false,
            recall: Recall::default(),
            runtime: None,
            health: None,
        },
    )
    .expect("mount upstream's panel");
    let app = web
        .protected
        .layer(axum::middleware::from_fn(
            |mut req: axum::extract::Request, next: axum::middleware::Next| async move {
                req.extensions_mut().insert(AuthLevel::Root);
                next.run(req).await
            },
        ))
        .merge(web.public);
    (store, app)
}

/// GET `uri` as a browser would (English, the panel's default language).
pub async fn get(app: &axum::Router, uri: &str) -> (StatusCode, String) {
    let request = Request::builder()
        .uri(uri)
        .header("accept", "text/html")
        .body(Body::empty())
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let body = axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap();
    (status, String::from_utf8_lossy(&body).into_owned())
}

/// GET `uri`, assert 200, and return the body.
pub async fn get_ok(app: &axum::Router, uri: &str) -> String {
    let (status, body) = get(app, uri).await;
    assert_eq!(status, StatusCode::OK, "GET {uri}: {}", &body[..body.len().min(400)]);
    body
}

/// GET a JSON route, assert 200, and parse it.
pub async fn get_json(app: &axum::Router, uri: &str) -> serde_json::Value {
    let body = get_ok(app, uri).await;
    serde_json::from_str(&body).unwrap_or_else(|e| panic!("GET {uri}: not JSON ({e}): {body}"))
}

/// Every GET screen of the inventory (docs/research/memory-panel-screens.md),
/// for the seed's ids: the read-only test requests them all.
pub fn screen_routes() -> Vec<String> {
    use seed::*;
    let p = format!("/web/w/{WORKSPACE}/{MAIN}");
    let mut routes: Vec<String> = [
        "/web", "/web?sort=sessions", "/web?sort=events", "/web?sort=pages",
        "/web?sort=open&state=open", "/web/inbox", "/web/inbox/notifications",
        "/web/workstreams", "/web/search", "/web/search?q=engine", "/web/graph",
        "/web/pending", "/web/health", "/web/docs", "/web/docs/features",
        "/web/docs/changelog", "/web/docs/features.md",
    ]
    .iter()
    .map(|s| (*s).to_owned())
    .collect();
    routes.extend([
        format!("/web/inbox?workspace={WORKSPACE}&project={MAIN}"),
        format!("/web/inbox?workspace={WORKSPACE}&project={MAIN}&box=outbox"),
        format!("/web/search?q=engine&workspace={WORKSPACE}&project={MAIN}&explain=1"),
        format!("{p}/graph"),
        format!("{p}/p/{VERSIONED_PAGE}"),
        format!("{p}/h/{VERSIONED_PAGE}"),
        format!("{p}/s/{S_DONE}"),
        format!("{p}/s/{S_OPEN}"),
        format!("{p}/s/{S_DONE}/retrievals"),
        format!("{p}/agents/claude-code"),
        format!("/web/w/{WORKSPACE}/{EMPTY}"),
    ]);
    for tab in ["overview", "agents", "tokens", "sessions", "knowledge"] {
        routes.push(format!("{p}?tab={tab}"));
    }
    routes
}

/// Every GET route of `/api/v1` the inventory lists, for the seed's ids.
pub fn api_routes() -> Vec<String> {
    use seed::*;
    let p = format!("/api/v1/workspaces/{WORKSPACE}/projects/{MAIN}");
    vec![
        "/api/v1/workspaces".into(),
        "/api/v1/projects".into(),
        format!("/api/v1/workspaces/{WORKSPACE}/overview"),
        format!("{p}/pages"),
        format!("{p}/pages/{VERSIONED_PAGE}"),
        format!("{p}/history/{VERSIONED_PAGE}"),
        format!("{p}/recent"),
        format!("{p}/briefing"),
        format!("{p}/overview"),
        format!("{p}/handoffs"),
        format!("{p}/sessions"),
        format!("{p}/sessions/{S_DONE}/observations"),
        format!("{p}/graph"),
        "/api/v1/graph".into(),
        "/api/v1/search?q=engine".into(),
        format!("/api/v1/search?q=engine&scope={WORKSPACE}/{MAIN}"),
        "/api/v1/docs".into(),
        "/api/v1/docs/features".into(),
        "/api/v1/docs/features/status".into(),
    ]
}
