//! Plan 40 B (docs/plans/40-memory-panel.md): the engine's panel data over
//! the A2 seed, against upstream's own panel over the same folder.
//!
//! The engine (the real binary, on its socket) serves the seed first; it is
//! stopped (store closed) and upstream's panel is mounted on the folder it
//! left, so both read the same bytes (the engine adds its `default/default`
//! project on start, which upstream then lists too).
//!
//! - Upstream's JSON API, answered by the engine's own handlers under
//!   `/cadex/memory/panel/api/v1`: every route of the inventory but `/docs`
//!   (left out, plan 40 B) and a few more queries equal upstream's real
//!   `api_router` answer, value for value.
//! - Our `extra/` routes (panel_api_screens.rs): each against what upstream's
//!   HTML screen shows, through the A2 HTML helpers.
//! - Reading every route through the engine leaves the folder byte for byte.

mod common;
mod panel;
#[path = "panel/screens.rs"]
mod screens;

use std::collections::BTreeMap;
use std::path::Path;

use serde_json::Value;

use common::{Engine, TOKEN, request, start};
use panel::{PANEL, api_routes, extra_routes, get_json, mount, seed, snapshot};
use panel::seed::{MAIN, S_DONE, VERSIONED_PAGE, WORKSPACE};

/// No import and no maintenance while the test reads: both wait this long
/// after the start (maintenance.rs, import.rs).
const ARGS: &[&str] = &["--keep-alive", "--import-delay-ms", "600000"];

/// GET `uri` from the engine with the session token; 200 and JSON.
pub fn engine_json(engine: &Engine, uri: &str) -> Value {
    let (status, body) = request(&engine.socket, "GET", uri, None, Some(TOKEN)).expect("the engine answers");
    assert_eq!(status, 200, "GET {uri}: {body}");
    serde_json::from_str(&body).unwrap_or_else(|e| panic!("GET {uri}: not JSON ({e}): {body}"))
}

/// The seed in `<tmp>/data`, served by the engine for every route in
/// `routes`, then the engine stopped. The answers, by route.
async fn through_engine(routes: &[String]) -> (tempfile::TempDir, BTreeMap<String, Value>) {
    let tmp = tempfile::tempdir().unwrap();
    seed::seed(&tmp.path().join("data")).await.expect("seed");
    let mut engine = start(tmp.path(), ARGS);
    let answers = routes.iter().map(|uri| (uri.clone(), engine_json(&engine, uri))).collect();
    engine.stop();
    (tmp, answers)
}

/// The `/api/v1` routes the engine answers: the inventory's, but the
/// guides (the native screen links to them on GitHub), and the queries the
/// screens send beyond the defaults.
fn served_api_routes() -> Vec<String> {
    let p = format!("/api/v1/workspaces/{WORKSPACE}/projects/{MAIN}");
    let mut routes: Vec<String> = api_routes().into_iter().filter(|r| !r.starts_with("/api/v1/docs")).collect();
    routes.extend([
        format!("/api/v1/projects?workspace={WORKSPACE}"),
        format!("/api/v1/graph?workspace={WORKSPACE}&project={MAIN}"),
        format!("{p}/history/{VERSIONED_PAGE}?limit=1&offset=1"),
        format!("{p}/recent?limit=2"),
        format!("{p}/briefing?limit=3"),
        format!("{p}/handoffs?all_owners=true"),
        format!("{p}/handoffs?state=open"),
        format!("{p}/sessions?include_open=true&limit=2&offset=1"),
        format!("{p}/sessions/{S_DONE}/observations?order=desc&limit=3&body_max_chars=200"),
        format!("{p}/sessions/{S_DONE}/observations?kinds=user-prompt,stop"),
        format!("/api/v1/search?q=engine&workspace={WORKSPACE}&project={MAIN}&limit=2"),
        format!("/api/v1/search?q=socket&scope={WORKSPACE}/{MAIN},{WORKSPACE}/site"),
        "/api/v1/search?q=".into(),
    ]);
    routes
}

#[tokio::test]
async fn upstream_api_answers_the_same_through_the_engine() {
    let upstream_routes = served_api_routes();
    let ours: Vec<String> = upstream_routes.iter().map(|r| format!("{PANEL}{r}")).collect();
    let (tmp, answers) = through_engine(&ours).await;
    let (store, app) = mount(&tmp.path().join("data"));
    for (theirs, ours) in upstream_routes.iter().zip(&ours) {
        let expected = get_json(&app, theirs).await;
        assert_eq!(answers[ours], expected, "{ours} differs from upstream's {theirs}");
    }
    store.close().await;
}

#[tokio::test]
async fn extra_routes_match_upstreams_screens() {
    let (tmp, answers) = through_engine(&extra_routes()).await;
    let (store, app) = mount(&tmp.path().join("data"));
    let ours = screens::Ours(&answers);
    screens::home(&app, &ours).await;
    screens::inbox(&app, &ours).await;
    screens::queues(&app, &ours).await;
    screens::health(&app, &ours).await;
    screens::project(&app, &ours).await;
    screens::agents(&app, &ours).await;
    screens::session(&app, &ours).await;
    store.close().await;
}

#[tokio::test]
async fn refusals_answer_as_upstream() {
    let p = format!("/api/v1/workspaces/{WORKSPACE}/projects");
    let refused = [
        format!("{p}/nowhere/pages"),
        format!("{p}/{MAIN}/pages/no/such.md"),
        format!("{p}/{MAIN}/history/no/such.md"),
        format!("{p}/{MAIN}/sessions/not-a-uuid/observations"),
        format!("{p}/{MAIN}/sessions/{S_DONE}/observations?order=sideways"),
        format!("{p}/{MAIN}/handoffs?state=lost"),
        "/api/v1/workspaces/nowhere/overview".into(),
        format!("/api/v1/graph?workspace={WORKSPACE}"),
        "/api/v1/search?q=x&scope=bad".into(),
        format!("/api/v1/search?q=x&scope={WORKSPACE}/{MAIN}&project={MAIN}"),
    ];
    let tmp = tempfile::tempdir().unwrap();
    seed::seed(&tmp.path().join("data")).await.expect("seed");
    let mut engine = start(tmp.path(), ARGS);
    let ours: Vec<(u16, String)> = refused
        .iter()
        .map(|r| request(&engine.socket, "GET", &format!("{PANEL}{r}"), None, Some(TOKEN)).expect("the engine answers"))
        .collect();
    engine.stop();
    let (store, app) = mount(&tmp.path().join("data"));
    for (route, (status, body)) in refused.iter().zip(ours) {
        let (theirs, expected) = panel::get(&app, route).await;
        assert_eq!(status, theirs.as_u16(), "{route}: {body}");
        let as_json = |b: &str| serde_json::from_str::<Value>(b).unwrap_or(Value::String(b.to_owned()));
        assert_eq!(as_json(&body), as_json(&expected), "{route}");
    }
    store.close().await;
}

/// Start the engine over `dir`'s parent layout, GET each of `routes`, stop
/// it (the store closes: queue drained, WAL checkpointed) and hash the data
/// folder (snapshot.rs).
fn cycle(root: &Path, routes: &[String]) -> snapshot::Snapshot {
    let mut engine = start(root, ARGS);
    for uri in routes {
        engine_json(&engine, uri);
    }
    engine.stop();
    drop(engine);
    snapshot::take(&root.join("data"))
}

#[tokio::test]
async fn reading_the_panel_through_the_engine_leaves_the_memory_untouched() {
    let tmp = tempfile::tempdir().unwrap();
    seed::seed(&tmp.path().join("data")).await.expect("seed");
    // As in panel_parity.rs: the baseline is the fixed point of a start and
    // a stop with no request (the engine's start adds its default project,
    // migrations and manifests once; `PRAGMA optimize` a statistics row).
    let mut before = cycle(tmp.path(), &[]);
    let mut settled = false;
    for _ in 0..4 {
        let again = cycle(tmp.path(), &[]);
        settled = again == before;
        before = again;
        if settled {
            break;
        }
    }
    assert!(settled, "starting and stopping the engine alone keeps changing the folder");
    let routes: Vec<String> =
        served_api_routes().iter().map(|r| format!("{PANEL}{r}")).chain(extra_routes()).collect();
    let after = cycle(tmp.path(), &routes);
    assert_eq!(snapshot::diff(&before, &after), Vec::<String>::new());
}
