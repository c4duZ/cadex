//! Writing and deleting a page from the Memory page (plan 22 phase H,
//! 2026-11-16), through the engine's own MCP tools in process
//! (`memory_write_page`, `memory_delete_page`, as auto_wiki.rs does): the
//! sanitizer, a new page version, the embedding and a commit of the wiki's
//! git, the same as when an agent writes.
//!
//! - `POST /cadex/memory/write-page?cwd&workspace&path`, the Markdown in the
//!   body, with or without frontmatter. `memory_write_page` clears the
//!   metadata a call leaves out, so a body without frontmatter is written
//!   with the page's current metadata, read from its file (what the owner
//!   edits is the text); a body with frontmatter carries its own. The title
//!   follows the body's `# H1` as upstream derives it; without one, the
//!   metadata's title is kept. → `{"ok":true,"path":P}`
//! - `POST /cadex/memory/delete-page?cwd&workspace&path` → `{"ok":true}`

use std::sync::Arc;

use ai_memory_core::PagePath;
use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::{Ctx, Params, Project, error, project_of};

/// The frontmatter keys `memory_write_page` takes as metadata, by the name
/// it has in the page's file and in the tool's arguments (the same:
/// `PageWriteMetadata` and `WritePageArgs` at fa0ec25).
const METADATA_KEYS: &[&str] = &[
    "kind", "entities", "abstract", "relations", "applies_to", "enforced_by", "source_files", "tags", "tier", "pinned",
    "expires_at",
];

/// The request's page path, checked as upstream checks one.
fn path_of(q: &std::collections::HashMap<String, String>) -> Result<String, Response> {
    let path = q.get("path").filter(|p| !p.is_empty()).ok_or_else(|| error(StatusCode::BAD_REQUEST, "path is required"))?;
    PagePath::new(path.clone()).map_err(|e| error(StatusCode::BAD_REQUEST, &format!("bad page path: {e}")))?;
    Ok(path.clone())
}

/// The frontmatter of the page's current file, or null.
fn current_frontmatter(ctx: &Ctx, project: &Project, path: &str) -> Value {
    let Some((ws, proj)) = project.ids else { return Value::Null };
    let file = ctx.wiki.project_root(ws, proj).join(path);
    let Ok(text) = std::fs::read_to_string(file) else { return Value::Null };
    ai_memory_wiki::parse(&text).map(|m| m.frontmatter).unwrap_or(Value::Null)
}

fn has_heading(body: &str) -> bool {
    body.lines().any(|l| l.starts_with("# "))
}

/// The tool's arguments: scope, path, body, and the metadata to keep.
pub(crate) fn write_args(project: &Project, path: &str, body: &str, metadata: &Value) -> Value {
    let mut args = project.tool_args();
    args["path"] = path.into();
    args["body"] = body.into();
    for key in METADATA_KEYS {
        if let Some(value) = metadata.get(key).filter(|v| !v.is_null()) {
            args[*key] = value.clone();
        }
    }
    if !has_heading(body)
        && let Some(title) = metadata.get("title").and_then(Value::as_str).filter(|t| !t.trim().is_empty())
    {
        args["title"] = title.into();
    }
    args
}

/// One tool call; its error as a 400 the client prints.
async fn call(ctx: &Ctx, name: &str, args: Value) -> Result<Value, Response> {
    let inner = ctx.inner()?;
    crate::auto_wiki::tool(&inner, name, args).await.map_err(|e| error(StatusCode::BAD_REQUEST, &format!("{e:#}")))
}

async fn record(ctx: &Ctx, q: &std::collections::HashMap<String, String>) {
    if let Ok(project) = project_of(ctx, q).await {
        let root = crate::projects_file::root_of(q.get("cwd").map_or("", String::as_str)).await;
        crate::projects_file::record_project(ctx, &project, root.as_deref());
    }
}

pub(crate) async fn write(State(ctx): State<Arc<Ctx>>, axum::extract::Query(q): Params, text: String) -> Response {
    let result = async {
        let project = project_of(&ctx, &q).await?;
        let path = path_of(&q)?;
        let given = ai_memory_wiki::parse(&text).map_err(|e| error(StatusCode::BAD_REQUEST, &format!("frontmatter: {e}")))?;
        let metadata = if given.frontmatter.is_object() { given.frontmatter.clone() } else { current_frontmatter(&ctx, &project, &path) };
        call(&ctx, "memory_write_page", write_args(&project, &path, &given.body, &metadata)).await?;
        Ok::<_, Response>(path)
    }
    .await;
    match result {
        Ok(path) => {
            // The write may have created the project.
            record(&ctx, &q).await;
            Json(json!({"ok": true, "path": path})).into_response()
        }
        Err(response) => response,
    }
}

pub(crate) async fn delete(State(ctx): State<Arc<Ctx>>, axum::extract::Query(q): Params) -> Response {
    let result = async {
        let project = project_of(&ctx, &q).await?;
        let path = path_of(&q)?;
        let mut args = project.tool_args();
        args["path"] = path.into();
        call(&ctx, "memory_delete_page", args).await
    }
    .await;
    match result {
        Ok(_) => Json(json!({"ok": true})).into_response(),
        Err(response) => response,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn project() -> Project {
        Project { workspace: "default".into(), project: "acme".into(), ids: None }
    }

    #[test]
    fn the_current_metadata_goes_with_a_new_body() {
        let fm = json!({"title": "Old", "kind": "gotcha", "tags": ["a"], "entities": ["wal"], "tier": "semantic",
            "abstract": "short", "type": "page", "generated": "x"});
        let args = write_args(&project(), "gotchas/wal.md", "Plain text.\n", &fm);
        assert_eq!(args["title"], "Old", "no H1: the title is kept");
        assert_eq!((args["kind"].as_str(), args["tier"].as_str(), args["abstract"].as_str()), (Some("gotcha"), Some("semantic"), Some("short")));
        assert_eq!(args["tags"], json!(["a"]));
        assert!(args.get("type").is_none() && args.get("generated").is_none(), "only the tool's metadata");
        let with_h1 = write_args(&project(), "gotchas/wal.md", "# New\n\nText.\n", &fm);
        assert!(with_h1.get("title").is_none(), "the H1 names the page");
        assert_eq!(with_h1["workspace"], "default");
    }
}
