//! Plan 40 B: each of the engine's `extra/` answers against what upstream's
//! HTML screen shows over the same folder (panel_api.rs runs them). The
//! markers are upstream's templates at the pinned commit (templates/*.html),
//! read through the A2 helpers (html.rs); the English strings are its
//! en/web.ftl.

#![allow(dead_code)]

use std::collections::BTreeMap;

use serde_json::Value;

use super::panel::seed::{MAIN, PROJECTS, S_DONE, VERSIONED_PAGE, VERSIONED_PAGE_TITLE, WORKSPACE};
use super::panel::{PANEL, get_json, get_ok, html};

/// The engine's answers, by route.
pub struct Ours<'a>(pub &'a BTreeMap<String, Value>);

impl Ours<'_> {
    pub fn get(&self, suffix: &str) -> &Value {
        let uri = format!("{PANEL}/extra/{suffix}");
        self.0.get(&uri).unwrap_or_else(|| panic!("{uri} not requested"))
    }
}

type App = axum::Router;

fn list<'v>(v: &'v Value, key: &str) -> &'v Vec<Value> {
    v[key].as_array().unwrap_or_else(|| panic!("no list {key} in {v}"))
}

fn strings(v: &[Value], key: &str) -> Vec<String> {
    v.iter().map(|r| r[key].as_str().unwrap_or_default().to_owned()).collect()
}

/// The text from `start` to the next `end` (exclusive), tags removed.
fn between(html: &str, start: &str, end: &str) -> String {
    let at = html.find(start).unwrap_or_else(|| panic!("no {start}"));
    let rest = &html[at + start.len()..];
    html::text(&rest[..rest.find(end).unwrap_or(rest.len())])
}

/// Upstream's `fmt_tokens` (templates.rs), to read its token cells.
fn fmt_tokens(n: u64) -> String {
    match n {
        1_000_000.. => format!("{:.1}M", n as f64 / 1_000_000.0),
        1_000.. => format!("{:.1}k", n as f64 / 1_000.0),
        _ => n.to_string(),
    }
}

/// The session ids an HTML table links to (`…/s/<id>`), in order.
fn linked_sessions(html: &str) -> Vec<String> {
    html::attr_values(html, "href").iter().filter_map(|h| h.split("/s/").nth(1)).map(|id| id.split(['?', '/']).next().unwrap().to_owned()).collect()
}

pub async fn home(app: &App, ours: &Ours<'_>) {
    let page = get_ok(app, "/web").await;
    let cards = html::chunks(&page, "<article class=\"project-card\"");
    let rows = list(ours.get("home"), "projects");
    let names: Vec<String> = cards.iter().map(|c| html::inner_texts(c, "h3")[0].clone()).collect();
    assert_eq!(strings(rows, "project"), names, "the cards, in upstream's order");
    for (row, card) in rows.iter().zip(&cards) {
        assert_eq!(row["pending_inbox"].as_u64(), html::attr_number(card, "data-inbox"), "{row}");
        let hint = between(card, "<p class=\"card-hint\">", "</p>");
        let shown = if hint == "No agent sessions yet" { 0 } else { hint.split(" · ").count() };
        assert_eq!(list(row, "agents").len(), shown, "agents of {row}: {hint}");
    }
    let main = rows.iter().find(|r| r["project"] == MAIN).unwrap();
    assert_eq!(main["agents"], serde_json::json!(["claude-code", "codex"]), "{main}");
    let capture = &ours.get("home")["capture"];
    assert_eq!(capture, &serde_json::json!({"accepted": 0, "dropped_by_policy": 0, "shed_saturated": 0, "shed_rate_limited": 0}));
    assert_eq!(ours.get("inbox/notifications"), &get_json(app, "/web/inbox/notifications").await);
}

pub async fn inbox(app: &App, ours: &Ours<'_>) {
    let mailbox = format!("workspace={WORKSPACE}&project={MAIN}");
    let pairs = [
        ("inbox".to_owned(), "/web/inbox".to_owned()),
        (format!("inbox?{mailbox}"), format!("/web/inbox?{mailbox}")),
        (format!("inbox?{mailbox}&state=claimed"), format!("/web/inbox?{mailbox}&state=claimed")),
        (format!("inbox?{mailbox}&state="), format!("/web/inbox?{mailbox}&state=")),
        (format!("inbox?{mailbox}&box=outbox"), format!("/web/inbox?{mailbox}&box=outbox")),
    ];
    let waiting: u64 = PROJECTS.iter().map(|p| p.pending_inbox).sum();
    for (suffix, theirs) in pairs {
        let page = get_ok(app, &theirs).await;
        let answer = ours.get(&suffix);
        let messages = list(answer, "messages");
        assert_eq!(strings(messages, "id"), html::attr_values(&page, "data-message-id"), "{suffix}");
        assert_eq!(strings(messages, "state"), html::attr_values(&page, "data-state"), "{suffix}");
        assert_eq!(answer["pending_total"], waiting, "{suffix}");
    }
    assert_eq!(list(ours.get(&format!("inbox?{mailbox}")), "messages").len() as u64, PROJECTS[0].pending_inbox);
}

pub async fn queues(app: &App, ours: &Ours<'_>) {
    let page = get_ok(app, "/web/workstreams").await;
    let streams = list(ours.get("workstreams"), "workstreams");
    assert_eq!(streams.len(), html::count(&page, "<tr>") - 1, "one row per workstream");
    let text = html::text(&page);
    for w in streams {
        let scope = format!("{}/{}", w["workspace"].as_str().unwrap(), w["project"].as_str().unwrap());
        assert!(text.contains(w["name"].as_str().unwrap()) && text.contains(&scope), "{w}");
    }
    let sorts = ["review", "review?sort=confidence-desc", &format!("review?sort=staged-desc&project={WORKSPACE}/{MAIN}")];
    for suffix in sorts {
        let theirs = suffix.replacen("review", "/web/pending", 1);
        let page = get_ok(app, &theirs).await;
        let answer = ours.get(suffix);
        let ids: Vec<String> =
            html::chunks(&page, "<li class=\"pending-item").iter().map(|c| html::attr_values(c, "data-id")[0].clone()).collect();
        let proposals = list(answer, "proposals");
        assert_eq!(strings(proposals, "id"), ids, "{suffix}: the same proposals in the same order");
        let summary = format!("{} shown · {} pending in {}", proposals.len(), answer["total"], answer["project_count"]);
        assert!(html::text(&page).contains(&summary), "{suffix}: {summary}");
    }
}

pub async fn health(app: &App, ours: &Ours<'_>) {
    let page = get_ok(app, "/web/health").await;
    let answer = ours.get("health");
    let theirs: Vec<String> = html::attr_values(&page, "data-check").into_iter().filter(|c| c != "none").collect();
    assert_eq!(strings(list(answer, "checks"), "id"), theirs, "the same failing checks: {answer}");
    let derived = &answer["derived"];
    assert!(derived["pages_rows"].as_u64() > Some(0), "{derived}");
    assert_eq!(answer["hooks"]["accepted"], 0);
    assert_eq!(answer["spool"]["pending"], 0);
    assert_eq!(answer["model"], "off", "--no-embeddings");
}

pub async fn project(app: &App, ours: &Ours<'_>) {
    let base = format!("/web/w/{WORKSPACE}/{MAIN}");
    let page = get_ok(app, &base).await;
    let summary = ours.get(&format!("workspaces/{WORKSPACE}/projects/{MAIN}/summary"));
    let t = &summary["tokens"];
    let tokens = format!("{} / {}", fmt_tokens(t["input_tokens"].as_u64().unwrap()), fmt_tokens(t["output_tokens"].as_u64().unwrap()));
    assert!(between(&page, "?tab=tokens#token-usage\"><span>", "</small>").contains(&tokens), "{tokens}");
    let badges: Vec<u64> = html::chunks(&page, "<span class=\"badge gap-1\" data-hue=\"violet\">")
        .iter()
        .map(|b| html::leading_number(between(b, "<span>·", "</span>").as_str()).unwrap())
        .collect();
    let by_agent: Vec<u64> = list(summary, "agents").iter().map(|a| a["sessions"].as_u64().unwrap()).collect();
    assert_eq!(by_agent, badges, "the agent badges");
    let mail = &summary["mailbox"];
    let subjects: Vec<String> = html::chunks(&page, "<div class=\"text-sm font-medium text-text truncate\">")
        .iter()
        .map(|c| between(c, ">", "</div>"))
        .collect();
    let ours_subjects: Vec<String> = list(mail, "messages").iter().map(|m| m["subject"].as_str().unwrap_or("(no subject)").to_owned()).collect();
    assert_eq!(ours_subjects, subjects, "the mailbox card");
    assert!(html::text(&page).contains(&format!("{} pending", mail["total"])), "{mail}");
    for (suffix, query) in [("sessions", ""), ("sessions?state=open", "?state=open"), ("sessions?sort=events", "?sort=events")] {
        let page = get_ok(app, &format!("{base}{query}")).await;
        let rows: Vec<String> = html::chunks(&page, "<tr data-session-agent").iter().flat_map(|r| linked_sessions(r)).collect();
        let answer = ours.get(&format!("workspaces/{WORKSPACE}/projects/{MAIN}/{suffix}"));
        assert_eq!(strings(list(answer, "sessions"), "session_id"), rows, "{suffix}");
    }
}

pub async fn agents(app: &App, ours: &Ours<'_>) {
    let p = format!("workspaces/{WORKSPACE}/projects/{MAIN}");
    let page = get_ok(app, &format!("/web/w/{WORKSPACE}/{MAIN}?tab=agents")).await;
    let cards = html::chunks(&page, "<article class=\"agent-card\"");
    let answer = list(ours.get(&format!("{p}/agents")), "agents");
    assert_eq!(strings(answer, "agent"), cards.iter().map(|c| html::attr_values(c, "data-agent")[0].clone()).collect::<Vec<_>>());
    for (card, html_card) in answer.iter().zip(&cards) {
        assert_eq!(card["coverage"].as_u64(), html::attr_number(html_card, "value"), "{card}");
        let recorded = format!("{} session", card["sessions"]);
        assert!(html::text(html_card).contains(&recorded), "{card}: {recorded}");
        let measured = format!("{}/{} sessions", card["measured_sessions"], card["sessions"]);
        assert!(html::text(html_card).contains(&measured), "{card}: {measured}");
    }
    for agent in ["claude-code", "codex"] {
        let page = get_ok(app, &format!("/web/w/{WORKSPACE}/{MAIN}/agents/{agent}")).await;
        let answer = ours.get(&format!("{p}/agents/{agent}"));
        assert_eq!(strings(list(answer, "sessions"), "session_id"), linked_sessions(&page), "{agent}");
        assert_eq!(answer["more"], false);
    }
    for (suffix, theirs) in [("tokens", format!("/web/w/{WORKSPACE}/{MAIN}?tab=tokens")), (&*format!("sessions/{S_DONE}/tokens"), format!("/web/w/{WORKSPACE}/{MAIN}/s/{S_DONE}"))] {
        let page = get_ok(app, &theirs).await;
        let answer = ours.get(&format!("{p}/{suffix}"));
        let metrics = &page[page.find("<div class=\"usage-metrics\">").expect("the usage panel")..];
        assert_eq!(html::numbers(metrics, "strong")[0], answer["call_count"].as_u64(), "{suffix}: captured calls");
        assert!(html::text(&page).contains(&format!("{} captured", answer["call_count"])), "{suffix}");
        assert_eq!(list(answer, "calls").len(), html::count(&page, "<tr data-call-row"), "{suffix}");
    }
}

pub async fn session(app: &App, ours: &Ours<'_>) {
    let p = format!("workspaces/{WORKSPACE}/projects/{MAIN}");
    let page = get_ok(app, &format!("/web/w/{WORKSPACE}/{MAIN}/s/{S_DONE}/retrievals")).await;
    let answer = ours.get(&format!("{p}/sessions/{S_DONE}/retrievals"));
    assert_eq!(list(answer, "records").len(), html::count(&page, "<li class=\"rounded border border-line bg-surface p-3\">"));
    assert_eq!(answer["total"], list(answer, "records").len());

    let page = html::text(&get_ok(app, &format!("/web/w/{WORKSPACE}/{MAIN}/p/{VERSIONED_PAGE}")).await);
    let answer = ours.get(&format!("{p}/evidence/{VERSIONED_PAGE}"));
    let (meta, evidence) = (&answer["meta"], &answer["evidence"]);
    assert_eq!((meta["path"].as_str(), meta["title"].as_str()), (Some(VERSIONED_PAGE), Some(VERSIONED_PAGE_TITLE)));
    assert!(meta.get("expired").is_none(), "not expired: {meta}");
    assert!(page.contains(evidence["version"].as_str().unwrap()), "the version id: {evidence}");
    assert!(page.contains(&format!("{} recorded citations", evidence["source_count"])), "{evidence}");
    assert!(page.contains(&format!("{} live readable edges", evidence["disagreement_count"])), "{evidence}");
}
