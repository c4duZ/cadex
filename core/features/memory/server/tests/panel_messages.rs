//! Plan 40 F (docs/plans/40-memory-panel.md): the inbox's writes through the
//! engine (`extra/messages…`, src/page/panel/messages.rs) against upstream's
//! own browser routes (`/web/messages…`), each over a seed of its own (the
//! message ids are random, so each side finds its own).
//!
//! The same script runs on both sides: send, the refusals of a send, hold a
//! queued message for editing, save it with new words, hold and discard
//! another, the refusals of an edit. Every step answers the same status and
//! the same words, and the mailbox ends the same: the subjects, the bodies
//! and the states, newest first.

mod common;
mod panel;

use serde_json::{Value, json};

use common::{TOKEN, request, start};
use panel::seed::{MAIN, SITE, WORKSPACE};
use panel::{PANEL, html, mount, seed};

const ARGS: &[&str] = &["--keep-alive", "--import-delay-ms", "600000"];

/// One side: a POST of JSON to a messages route ("" or "/<id>/edit"), and
/// a read of the mailbox (`cadex`'s, every state).
trait Side {
    async fn post(&self, route: &str, body: &Value) -> (u16, Value);
    /// The mailbox, newest first: (id, subject, body, state).
    async fn mailbox(&self) -> Vec<(String, String, String, String)>;
}

struct Ours(std::path::PathBuf);

impl Side for Ours {
    async fn post(&self, route: &str, body: &Value) -> (u16, Value) {
        let (status, text) = request(&self.0, "POST", &format!("{PANEL}/extra/messages{route}"), Some(&body.to_string()), Some(TOKEN))
            .expect("the engine answers");
        (status, serde_json::from_str(&text).unwrap_or(Value::String(text)))
    }

    async fn mailbox(&self) -> Vec<(String, String, String, String)> {
        let uri = format!("{PANEL}/extra/inbox?workspace={WORKSPACE}&project={MAIN}&state=");
        let (_, text) = request(&self.0, "GET", &uri, None, Some(TOKEN)).expect("the engine answers");
        let read: Value = serde_json::from_str(&text).unwrap();
        let field = |m: &Value, k: &str| m[k].as_str().unwrap_or("").to_owned();
        read["messages"].as_array().unwrap().iter().map(|m| (field(m, "id"), field(m, "subject"), field(m, "body"), field(m, "state"))).collect()
    }
}

struct Theirs(axum::Router);

impl Side for Theirs {
    async fn post(&self, route: &str, body: &Value) -> (u16, Value) {
        use tower::ServiceExt;
        let request = axum::http::Request::builder()
            .method("POST")
            .uri(format!("/web/messages{route}"))
            .header("content-type", "application/json")
            .header("x-ai-memory-ui", "1")
            .body(axum::body::Body::from(body.to_string()))
            .unwrap();
        let response = self.0.clone().oneshot(request).await.unwrap();
        let status = response.status().as_u16();
        let bytes = axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let text = String::from_utf8_lossy(&bytes).into_owned();
        (status, serde_json::from_str(&text).unwrap_or(Value::String(text)))
    }

    async fn mailbox(&self) -> Vec<(String, String, String, String)> {
        let page = panel::get_ok(&self.0, &format!("/web/inbox?workspace={WORKSPACE}&project={MAIN}&state=")).await;
        let ids = html::attr_values(&page, "data-message-id");
        let subjects = html::attr_values(&page, "data-subject");
        let states = html::attr_values(&page, "data-state");
        let bodies: Vec<String> = html::chunks(&page, r#"<p class="message-body">"#)
            .iter()
            .map(|c| html::text(&c[..c.find("</p>").unwrap_or(c.len())]))
            .collect();
        (0..ids.len()).map(|i| (ids[i].clone(), subjects[i].clone(), bodies[i].clone(), states[i].clone())).collect()
    }
}

fn compose(to_project: &str, agent: &str, subject: &str, body: &str) -> Value {
    json!({"from_workspace": WORKSPACE, "from_project": MAIN, "to_workspace": WORKSPACE, "to_project": to_project,
           "to_agent": agent, "subject": subject, "body": body})
}

fn mailbox_of(extra: Value) -> Value {
    let mut v = json!({"workspace": WORKSPACE, "project": MAIN});
    if let (Some(v), Value::Object(extra)) = (v.as_object_mut(), extra) {
        v.extend(extra);
    }
    v
}

/// The script: every step's status and answer, ids masked (they differ by side).
async fn script(side: &impl Side) -> (Vec<(u16, Value)>, Vec<(String, String, String)>) {
    let mut out = Vec::new();
    let mask = |(status, mut answer): (u16, Value)| {
        if let Some(id) = answer.get_mut("message_id") {
            *id = Value::String(if id.as_str().is_some_and(|s| !s.is_empty()) { "<id>".into() } else { "<none>".into() });
        }
        (status, answer)
    };
    out.push(mask(side.post("", &compose(MAIN, "claude-code", "  Panel request ", " Do the thing \n")).await));
    out.push(mask(side.post("", &compose(SITE, "codex", "", "Nobody there")).await));
    out.push(mask(side.post("", &compose(MAIN, "nobody", "", "Unknown agent")).await));
    out.push(mask(side.post("", &compose(MAIN, "claude-code", "", "   ")).await));
    out.push(mask(side.post("", &compose(MAIN, "codex", &"s".repeat(201), "Long subject")).await));
    out.push(mask(side.post("", &compose(MAIN, "claude-code", "", &"b".repeat(8_001))).await));
    // Unknown project: upstream answers its HTML not-found page, so only the status counts.
    let (status, _) = side.post("", &compose("nowhere", "claude-code", "", "x")).await;
    out.push((status, Value::Null));

    let mail = side.mailbox().await;
    let pending: Vec<&String> = mail.iter().filter(|m| m.3 == "pending").map(|m| &m.0).collect();
    let claimed = &mail.iter().find(|m| m.3 == "claimed").expect("the seed's collected message").0;
    let (first, second) = (pending[0].clone(), pending[1].clone());
    let held = side.post(&format!("/{first}/edit"), &mailbox_of(json!({}))).await;
    out.push(mask(held));
    out.push(mask(side.post(&format!("/{first}/save"), &mailbox_of(json!({"subject": "", "body": "  "}))).await));
    out.push(mask(side.post(&format!("/{first}/save"), &mailbox_of(json!({"subject": " Edited ", "body": " New words "}))).await));
    out.push(mask(side.post(&format!("/{first}/save"), &mailbox_of(json!({"subject": "Again", "body": "Again"}))).await));
    out.push(mask(side.post(&format!("/{second}/edit"), &mailbox_of(json!({}))).await));
    out.push(mask(side.post(&format!("/{second}/release"), &mailbox_of(json!({}))).await));
    out.push(mask(side.post(&format!("/{second}/release"), &mailbox_of(json!({}))).await));
    out.push(mask(side.post(&format!("/{claimed}/edit"), &mailbox_of(json!({}))).await));
    out.push(mask(side.post("/not-an-id/edit", &mailbox_of(json!({}))).await));
    // A message of another mailbox: site's has none of cadex's.
    let elsewhere = json!({"workspace": WORKSPACE, "project": SITE});
    out.push(mask(side.post(&format!("/{second}/edit"), &elsewhere).await));
    let after = side.mailbox().await.into_iter().map(|(_, subject, body, state)| (subject, body, state)).collect();
    (out, after)
}

#[tokio::test]
async fn messages_answer_as_upstream() {
    let ours_dir = tempfile::tempdir().unwrap();
    seed::seed(&ours_dir.path().join("data")).await.expect("seed");
    let mut engine = start(ours_dir.path(), ARGS);
    let ours = script(&Ours(engine.socket.clone())).await;
    engine.stop();

    let theirs_dir = tempfile::tempdir().unwrap();
    seed::seed(&theirs_dir.path().join("data")).await.expect("seed");
    let (store, app) = mount(&theirs_dir.path().join("data"));
    let theirs = script(&Theirs(app)).await;
    store.close().await;

    assert_eq!(ours.0.len(), theirs.0.len());
    for (step, (a, b)) in ours.0.iter().zip(&theirs.0).enumerate() {
        assert_eq!(a, b, "step {step}");
    }
    assert_eq!(ours.1, theirs.1, "the mailbox after the script");
    // What the script did shows: the new message, newest, was held and saved with new words;
    // the seed's two queued ones are still queued, the collected one still collected.
    let states: Vec<&str> = ours.1.iter().map(|m| m.2.as_str()).collect();
    assert_eq!(states, ["pending", "pending", "pending", "claimed"]);
    assert_eq!((ours.1[0].0.as_str(), ours.1[0].1.as_str()), ("Edited", "New words"));
}
