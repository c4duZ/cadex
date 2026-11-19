//! Plan 40 A2 (docs/plans/40-memory-panel.md): upstream's own panel over the
//! fake memory folder. Every screen and `/api/v1` route of the inventory
//! (docs/research/memory-panel-screens.md) answers 200 and shows what the
//! seed wrote, read through the HTML helpers phase B will compare our JSON
//! against; and reading all of them leaves the folder byte for byte as it was.

mod panel;

use panel::seed::{self, GLOBAL, MAIN, PROJECTS, SITE, WORKSPACE};
use panel::{api_routes, get_json, get_ok, html, mount, screen_routes, snapshot};

async fn seeded() -> tempfile::TempDir {
    let tmp = tempfile::tempdir().unwrap();
    seed::seed(tmp.path()).await.expect("seed");
    tmp
}

#[tokio::test]
async fn every_screen_and_api_route_answers() {
    let tmp = seeded().await;
    let (store, app) = mount(tmp.path());
    for uri in screen_routes().iter().chain(api_routes().iter()) {
        get_ok(&app, uri).await;
    }
    store.close().await;
}

#[tokio::test]
async fn overview_shows_the_seed_counts() {
    let tmp = seeded().await;
    let (store, app) = mount(tmp.path());
    let page = get_ok(&app, "/web").await;
    let metrics: Vec<&str> = html::chunks(&page, "<a class=\"metric-card");
    let numbers: Vec<Option<u64>> = metrics.iter().map(|m| html::numbers(m, "strong")[0]).collect();
    let sum = |f: fn(&seed::ProjectCounts) -> u64| Some(PROJECTS.iter().map(f).sum::<u64>());
    assert_eq!(
        numbers,
        vec![
            Some(PROJECTS.len() as u64),
            sum(|p| p.sessions),
            sum(|p| p.observations),
            sum(|p| p.pages),
            sum(|p| p.open_sessions),
        ],
        "the five overview counters"
    );

    let cards = html::chunks(&page, "<article class=\"project-card\"");
    assert_eq!(cards.len(), PROJECTS.len());
    for expected in &PROJECTS {
        let card = cards
            .iter()
            .find(|c| html::inner_texts(c, "h3").first().map(String::as_str) == Some(expected.name))
            .unwrap_or_else(|| panic!("no card for {}", expected.name));
        let shown = html::numbers(card, "strong");
        assert_eq!(
            shown,
            vec![Some(expected.sessions), Some(expected.observations), Some(expected.pages), Some(expected.open_sessions)],
            "card of {}",
            expected.name
        );
        assert_eq!(html::attr_number(card, "data-inbox"), Some(expected.pending_inbox), "{}", expected.name);
    }
    store.close().await;
}

#[tokio::test]
async fn api_projects_agree_with_the_html_cards() {
    let tmp = seeded().await;
    let (store, app) = mount(tmp.path());
    let json = get_json(&app, "/api/v1/projects").await;
    let rows = json.as_array().expect("projects array");
    assert_eq!(rows.len(), PROJECTS.len());
    for expected in &PROJECTS {
        let row = rows.iter().find(|r| r["project_name"] == expected.name).unwrap();
        assert_eq!(row["workspace_name"], WORKSPACE);
        assert_eq!(row["session_count"], expected.sessions, "{}", expected.name);
        assert_eq!(row["observation_count"], expected.observations, "{}", expected.name);
        assert_eq!(row["page_count"], expected.pages, "{}", expected.name);
        assert_eq!(row["open_session_count"], expected.open_sessions, "{}", expected.name);
    }
    store.close().await;
}

#[tokio::test]
async fn inbox_workstream_and_proposals_show() {
    let tmp = seeded().await;
    let (store, app) = mount(tmp.path());
    let pending_mail: u64 = PROJECTS.iter().map(|p| p.pending_inbox).sum();
    let notifications = get_json(&app, "/web/inbox/notifications").await;
    assert_eq!(notifications["pending"], pending_mail);
    assert_eq!(notifications["projects"][0]["project"], MAIN);

    let mailbox = format!("/web/inbox?workspace={WORKSPACE}&project={MAIN}");
    let inbox = get_ok(&app, &mailbox).await;
    let rows = html::chunks(&inbox, "<details class=\"mail-row\"");
    assert_eq!(html::attr_values(&inbox, "data-state"), vec!["pending"; pending_mail as usize]);
    assert!(html::text(rows[0]).contains("Site needs the engine doc"), "newest first");
    let collected = get_ok(&app, &format!("{mailbox}&state=claimed")).await;
    assert_eq!(html::attr_values(&collected, "data-state"), vec!["claimed"]);
    assert!(html::text(&collected).contains("Collected request"));

    let streams = html::text(&get_ok(&app, "/web/workstreams").await);
    assert!(streams.contains(seed::WORKSTREAM_NAME), "{streams}");
    assert!(streams.contains(&format!("{WORKSPACE}/{MAIN}")), "{streams}");

    let pending = get_ok(&app, "/web/pending").await;
    let proposals: u64 = PROJECTS.iter().map(|p| p.pending_proposals).sum();
    let scopes = PROJECTS.iter().filter(|p| p.pending_proposals > 0).count();
    assert_eq!(html::chunks(&pending, "<li class=\"pending-item").len() as u64, proposals);
    let summary = html::text(&pending);
    assert!(summary.contains(&format!("{proposals} shown · {proposals} pending in {scopes}")), "{summary}");
    store.close().await;
}

#[tokio::test]
async fn page_history_graph_and_handoff_show() {
    let tmp = seeded().await;
    let (store, app) = mount(tmp.path());
    let api = format!("/api/v1/workspaces/{WORKSPACE}/projects/{MAIN}");
    let history = get_json(&app, &format!("{api}/history/{}", seed::VERSIONED_PAGE)).await;
    assert_eq!(history["total"], seed::VERSIONS);
    assert_eq!(history["diff"]["status"], "changed");
    let page = html::text(&get_ok(&app, &format!("/web/w/{WORKSPACE}/{MAIN}/h/{}", seed::VERSIONED_PAGE)).await);
    assert!(page.contains(&format!("{} versions", seed::VERSIONS)), "{page}");

    let one = get_json(&app, &format!("{api}/pages/{}", seed::VERSIONED_PAGE)).await;
    assert_eq!(one["title"], seed::VERSIONED_PAGE_TITLE);
    assert_eq!(one["backlinks"].as_array().map(Vec::len), Some(3), "socket.md, index.md and site's deploy.md: {one}");

    let graph = get_json(&app, &format!("{api}/graph")).await;
    assert_eq!(graph["edges"].as_array().map(Vec::len), Some(3), "{graph}");
    let global = get_json(&app, "/api/v1/graph").await;
    assert_eq!(global["edges"].as_array().map(Vec::len), Some(1), "{SITE} to {MAIN}: {global}");

    let handoffs = get_json(&app, &format!("{api}/handoffs")).await;
    assert!(handoffs.to_string().contains(seed::HANDOFF_SUMMARY), "{handoffs}");
    let sessions = get_json(&app, &format!("{api}/sessions?include_open=true")).await;
    assert!(sessions.to_string().contains(seed::S_OPEN), "{sessions}");
    let global_pages = get_json(&app, &format!("/api/v1/workspaces/{WORKSPACE}/projects/{GLOBAL}/pages")).await;
    assert!(global_pages.to_string().contains("_rules/language.md"), "{global_pages}");
    store.close().await;
}

/// Open the store and the panel over `dir`, GET each of `routes`, close the
/// store (drain and checkpoint) and hash the folder (snapshot.rs).
async fn cycle(dir: &std::path::Path, routes: &[String]) -> snapshot::Snapshot {
    let (store, app) = mount(dir);
    for uri in routes {
        get_ok(&app, uri).await;
    }
    drop(app);
    store.close().await;
    drop(store);
    snapshot::take(dir)
}

#[tokio::test]
async fn reading_every_route_leaves_the_memory_untouched() {
    let tmp = seeded().await;
    // The baseline is the fixed point of open+close with no request:
    // `Store::open` runs `PRAGMA optimize`, which on the second open after the
    // seed added a `sqlite_stat1` row (backfill_watermarks, measured
    // 2026-11-19) and then stops. Statistics, not memory, but bytes all the same.
    let mut before = cycle(tmp.path(), &[]).await;
    let mut settled = false;
    for _ in 0..4 {
        let again = cycle(tmp.path(), &[]).await;
        settled = again == before;
        before = again;
        if settled {
            break;
        }
    }
    assert!(settled, "opening and closing the store alone keeps changing the folder");
    assert!(before.keys().any(|p| p.starts_with("db")), "the database is hashed");
    assert!(before.keys().any(|p| p.extension().is_some_and(|e| e == "md")), "the wiki is hashed");

    let routes: Vec<String> = screen_routes().into_iter().chain(api_routes()).collect();
    let after = cycle(tmp.path(), &routes).await;
    assert_eq!(snapshot::diff(&before, &after), Vec::<String>::new());
}
