//! `POST /cadex/memory/reindex?cwd=<dir>[&workspace=]`: take in the edits
//! made to the project's wiki files outside the engine (Cadex's Markdown tab
//! writes the file; another editor) and commit them (the spec's
//! memory.reindex, plan 22 phase H, 2026-11-16). → `{"ok":true,"changed":N}`
//!
//! Upstream does this with its wiki watcher's reconcile pass (every page file
//! through `Wiki::reindex_page`, which keeps the file and makes a new
//! version only when the text changed); Cadex runs with the watcher off
//! (nothing by a clock), and upstream's walker is private, so the walk below
//! is **copied** from crates/ai-memory-wiki/src/watcher.rs at commit
//! fa0ec25dbe987b7574a7487ecf92f0873040c2f2 (2026-11-16):
//! `walk_markdown_partial` → [`walk`] (without fingerprints and the partial
//! flag, which only its reconcile-delete safety net reads), `is_markdown`,
//! `is_tempfile`, `is_manifest_filename` and `is_reserved_page_file` →
//! [`is_page_file`], `page_path_relative_to` → [`relative`]. As upstream's
//! reconcile, a file removed is not a page deleted (memory_delete_page is).
//! Then each changed file is reported to the wiki's git (`mark_written`, as
//! the watcher does) and the wiki committed (`Wiki::commit_all`).

use std::path::Path;
use std::sync::Arc;

use ai_memory_core::PagePath;
use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::json;

use super::{Ctx, Params, error, project_of};

fn relative(root: &Path, abs: &Path) -> Option<PagePath> {
    let rel = abs.strip_prefix(root).ok()?;
    let parts: Vec<&str> = rel.components().filter_map(|c| c.as_os_str().to_str()).collect();
    PagePath::new(parts.join("/")).ok()
}

/// A page file and not: a temporary write, the scope manifest, the
/// bootstrap file, or a raw hook ledger (`log.md`, `log-YYYY-MM.md` opening
/// with a hook log entry).
fn is_page_file(abs: &Path, page: &PagePath) -> bool {
    let name = abs.file_name().and_then(|n| n.to_str()).unwrap_or("");
    if abs.extension().is_none_or(|e| e != "md") || name.starts_with(".ai-memory-tmp.") {
        return false;
    }
    if name == "_meta.md" || page.as_str() == "bootstrap.md" {
        return false;
    }
    if page.as_str() == "_pending" || page.as_str().starts_with("_pending/") {
        return false;
    }
    if ai_memory_core::log_ledger::is_log_ledger_path(page.as_str()) {
        // Upstream's `opens_with_log_ledger`: the first GATE_PREFIX_BYTES,
        // cut at the last whole line when the file fills them.
        let gate = ai_memory_core::log_ledger::GATE_PREFIX_BYTES;
        let text = std::fs::read(abs).unwrap_or_default();
        let mut head = &text[..text.len().min(gate)];
        if text.len() >= gate {
            head = &head[..head.iter().rposition(|b| *b == b'\n').map_or(0, |at| at + 1)];
        }
        let ledger = std::str::from_utf8(head).is_ok_and(ai_memory_core::log_ledger::body_opens_with_log_ledger);
        return !ledger;
    }
    true
}

/// The project's page files, symlinks and the `_pending/` sidecars skipped.
fn walk(root: &Path) -> std::io::Result<Vec<PagePath>> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let read = match std::fs::read_dir(&dir) {
            Ok(read) => read,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
            Err(e) => return Err(e),
        };
        for entry in read {
            let path = entry?.path();
            let meta = std::fs::symlink_metadata(&path)?;
            if meta.file_type().is_symlink() {
                continue;
            }
            if meta.is_dir() {
                if path.strip_prefix(root).ok().and_then(|r| r.components().next()).is_some_and(|c| c.as_os_str() == "_pending") {
                    continue;
                }
                stack.push(path);
            } else if meta.is_file()
                && let Some(page) = relative(root, &path)
                && is_page_file(&path, &page)
            {
                out.push(page);
            }
        }
    }
    Ok(out)
}

pub(crate) async fn handle(State(ctx): State<Arc<Ctx>>, axum::extract::Query(q): Params) -> Response {
    let project = match project_of(&ctx, &q).await {
        Ok(project) => project,
        Err(response) => return response,
    };
    let Some((ws, proj)) = project.ids else { return Json(json!({"ok": true, "changed": 0})).into_response() };
    let root = ctx.wiki.project_root(ws, proj);
    let walked = root.clone();
    let pages = match tokio::task::spawn_blocking(move || walk(&walked)).await {
        Ok(Ok(pages)) => pages,
        Ok(Err(e)) => return error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()),
        Err(e) => return error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()),
    };
    let before: std::collections::HashMap<String, ai_memory_core::PageId> = match ctx.reader.latest_page_ids(ws, proj).await {
        Ok(rows) => rows.into_iter().map(|(id, path)| (path.as_str().to_owned(), id)).collect(),
        Err(e) => return error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()),
    };
    let mut changed = 0usize;
    for page in pages {
        let key = page.as_str().to_owned();
        match ctx.wiki.reindex_page(ws, proj, page).await {
            Ok(id) if before.get(&key) != Some(&id) => {
                // Reported as the watcher reports an outside write, so the
                // commit stages it without sweeping the whole tree.
                ctx.wiki.git().mark_written(&root.join(&key));
                changed += 1;
            }
            Ok(_) => {}
            // As upstream's reconcile: one bad file does not stop the pass.
            Err(e) => tracing::warn!(path = %key, error = %e, "reindex of a wiki file failed"),
        }
    }
    if changed > 0 {
        let wiki = ctx.wiki.clone();
        let message = format!("cadex reindex: {}/{}", project.workspace, project.project);
        let committed = tokio::task::spawn_blocking(move || wiki.commit_all(&message)).await;
        if let Ok(Err(e)) = committed {
            return error(StatusCode::INTERNAL_SERVER_ERROR, &format!("reindexed {changed}, not committed: {e}"));
        }
    }
    Json(json!({"ok": true, "changed": changed})).into_response()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_walk_keeps_pages_and_skips_what_is_not_one() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        for (rel, text) in [
            ("a.md", "# A\n"),
            ("notes/b.md", "# B\n"),
            ("_meta.md", "---\nproject: x\n---\n"),
            ("bootstrap.md", "x"),
            ("log.md", "## [2026-11-16T10:00:00Z] session-start | s\n"),
            ("_pending/auto-improve/x.md", "# P\n"),
            ("notes/.ai-memory-tmp.123.md", "t"),
            ("notes/c.txt", "c"),
        ] {
            let path = root.join(rel);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, text).unwrap();
        }
        std::os::unix::fs::symlink(root.join("a.md"), root.join("link.md")).unwrap();
        let mut found: Vec<String> = walk(root).unwrap().iter().map(|p| p.as_str().to_owned()).collect();
        found.sort();
        assert_eq!(found, vec!["a.md", "notes/b.md"]);
    }
}
