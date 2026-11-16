//! Claude's automatic memories in the project's wiki (plan 22, phase C):
//! each topic file of an automatic memory folder (auto_index.rs) is a page
//! `auto/<file>` of kind `fact` in the project's scope, written through the
//! engine's own `memory_write_page` (in process, past the token check, as
//! the spool replays go), so the search finds it and the wiki's git keeps
//! its history; a topic file deleted deletes its page. A page is written
//! only when its file changed since the last write (a hash per file in
//! `<data-dir>/auto-pages/`), so a reconcile at every start costs reads only.
//!
//! The folder's project comes from the `project.json` the app writes beside
//! the memories (apps/macos/features/memory/MemoryProject.swift):
//! `{"root": <main checkout>, "account": <account key> | null}`; the
//! workspace is the account's (memory.shareAcrossAccounts off) or `default`,
//! and the project is named as the hook router names the root's
//! (`derive_project_name` with the main-repo-root rule).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use ai_memory_consolidate::{ProjectNameStrategy, derive_project_name};
use anyhow::{Context, Result, bail};
use axum::Router;
use axum::body::Body;
use axum::http::{Request, header};
use sha2::{Digest, Sha256};
use tower::ServiceExt;

use crate::auto_index::{Topic, topics};

pub(crate) const PROJECT_FILE: &str = "project.json";
/// Where a page of a topic file goes in the project's wiki.
const PAGE_PREFIX: &str = "auto/";

/// The project an automatic memory folder belongs to.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Scope {
    pub(crate) workspace: String,
    pub(crate) project: String,
}

/// The scope a folder's project.json names. A folder whose name is not its
/// root's key (crate::project_key) was not made by the app: left alone.
pub(crate) fn scope(dir: &Path) -> Result<Scope> {
    let text = std::fs::read_to_string(dir.join(PROJECT_FILE)).context("no project.json")?;
    let value: serde_json::Value = serde_json::from_str(&text).context("project.json")?;
    let root = value.get("root").and_then(|r| r.as_str()).context("project.json without root")?;
    let key = crate::project_key::key_of_root(Path::new(root));
    if dir.file_name().and_then(|n| n.to_str()) != Some(key.as_str()) {
        bail!("folder is not named by its root's key {key}");
    }
    let workspace = value.get("account").and_then(|a| a.as_str()).filter(|a| !a.is_empty());
    let (project, _) = derive_project_name(Path::new(root), ProjectNameStrategy::MainRepoRoot)
        .context("no project name for the root")?;
    Ok(Scope { workspace: workspace.unwrap_or(ai_memory_core::DEFAULT_WORKSPACE_NAME).to_string(), project })
}

/// One MCP tool call through the router; the result's `structuredContent`
/// or text, or why it failed.
pub(crate) async fn tool(router: &Router, name: &str, arguments: serde_json::Value) -> Result<serde_json::Value> {
    let call = serde_json::json!({
        "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": arguments},
    });
    let request = Request::post("/mcp")
        .header(header::HOST, "localhost")
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT, "application/json, text/event-stream")
        .body(Body::from(call.to_string()))?;
    let response = router.clone().oneshot(request).await.unwrap_or_else(|never| match never {});
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), 4 << 20).await?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).with_context(|| format!("{name}: {status}"))?;
    let result = value.get("result").cloned().with_context(|| format!("{name}: {value}"))?;
    if result.get("isError").and_then(|e| e.as_bool()) == Some(true) {
        bail!("{name}: {result}");
    }
    Ok(result)
}

/// A page for a topic file: its name as the title, its description, its
/// text, and the session that saved it.
fn page_body(topic: &Topic) -> String {
    let mut body = format!("# {}\n\n", topic.name.trim());
    if let Some(d) = &topic.description {
        body.push_str(d.trim());
        body.push_str("\n\n");
    }
    body.push_str(topic.body.trim());
    body.push('\n');
    if let Some(origin) = &topic.origin_session {
        body.push_str(&format!("\nSaved by Claude's automatic memory in session `{origin}` (`{}`).\n", topic.file));
    }
    body
}

async fn write_page(router: &Router, scope: &Scope, topic: &Topic) -> Result<()> {
    let args = serde_json::json!({
        "workspace": scope.workspace, "project": scope.project, "path": format!("{PAGE_PREFIX}{}", topic.file),
        "body": page_body(topic), "kind": "fact", "tags": ["claude-auto-memory"],
    });
    // The origin session as the page's evidence, when the store has it in
    // this project; a session it does not know (saved before Cadex, or in
    // another project) refuses the write, which then goes without it.
    if let Some(origin) = &topic.origin_session {
        let mut with_origin = args.clone();
        with_origin["session_id"] = origin.clone().into();
        if tool(router, "memory_write_page", with_origin).await.is_ok() {
            return Ok(());
        }
    }
    tool(router, "memory_write_page", args).await.map(|_| ())
}

fn hash(text: &str) -> String {
    Sha256::digest(text.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}

/// The hashes of the files last written as pages, by file name.
type Written = BTreeMap<String, String>;

fn state_path(data_dir: &Path, dir: &Path) -> PathBuf {
    let rel = dir.strip_prefix(data_dir.join("auto")).unwrap_or(dir);
    let name: String = rel.to_string_lossy().chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect();
    data_dir.join("auto-pages").join(format!("{name}.json"))
}

fn load(path: &Path) -> Written {
    std::fs::read(path).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn save(path: &Path, written: &Written) -> Result<()> {
    std::fs::create_dir_all(path.parent().context("state folder")?)?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_vec(written)?)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// What one sync did.
#[derive(Debug, Default, PartialEq)]
pub(crate) struct Synced {
    pub(crate) written: usize,
    pub(crate) deleted: usize,
}

/// Bring the folder's pages in line with its topic files.
pub(crate) async fn sync(router: &Router, data_dir: &Path, dir: &Path) -> Result<Synced> {
    let scope = scope(dir)?;
    let state = state_path(data_dir, dir);
    let mut written = load(&state);
    let mut done = Synced::default();
    let present = topics(dir);
    for topic in &present {
        let h = hash(&topic.raw);
        if written.get(&topic.file) == Some(&h) {
            continue;
        }
        match write_page(router, &scope, topic).await {
            Ok(()) => {
                written.insert(topic.file.clone(), h);
                done.written += 1;
            }
            Err(error) => tracing::warn!(file = %topic.file, error = %format!("{error:#}"), "automatic memory page not written"),
        }
    }
    let gone: Vec<String> = written.keys().filter(|f| !present.iter().any(|t| &&t.file == f)).cloned().collect();
    for file in gone {
        let args = serde_json::json!({
            "workspace": scope.workspace, "project": scope.project, "path": format!("{PAGE_PREFIX}{file}"),
        });
        // A page already gone (deleted by hand) counts as deleted.
        if let Err(error) = tool(router, "memory_delete_page", args).await {
            tracing::info!(%file, error = %format!("{error:#}"), "automatic memory page not deleted");
        }
        written.remove(&file);
        done.deleted += 1;
    }
    if done != Synced::default() {
        save(&state, &written)?;
    }
    Ok(done)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_folder_maps_back_to_its_project_only_when_the_app_made_it() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path().join("acme");
        std::fs::create_dir_all(&root).unwrap();
        let key = crate::project_key::key_of_root(&root);
        let dir = tmp.path().join("auto").join("acct").join(&key);
        std::fs::create_dir_all(&dir).unwrap();
        let json = serde_json::json!({"root": root, "account": "-Users-a--claude-x"});
        std::fs::write(dir.join(PROJECT_FILE), json.to_string()).unwrap();
        assert_eq!(scope(&dir).unwrap(), Scope { workspace: "-Users-a--claude-x".into(), project: "acme".into() });
        std::fs::write(dir.join(PROJECT_FILE), serde_json::json!({"root": root, "account": null}).to_string()).unwrap();
        assert_eq!(scope(&dir).unwrap().workspace, "default");

        let stray = tmp.path().join("auto").join("not-a-key");
        std::fs::create_dir_all(&stray).unwrap();
        std::fs::write(stray.join(PROJECT_FILE), json.to_string()).unwrap();
        assert!(scope(&stray).is_err());
        assert_eq!(state_path(tmp.path(), &dir), tmp.path().join(format!("auto-pages/acct-{key}.json")));
    }
}
