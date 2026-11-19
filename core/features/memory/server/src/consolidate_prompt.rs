//! `GET /cadex/consolidate?session_id=<id>&reason=<context|ready|asked>[&cwd=…][&workspace=…]`:
//! the request that makes the session's own Claude consolidate the session
//! into the project memory (plan 22 phase F: "consolidação na sessão, sem
//! token"; `cadex memory-hook` puts it in a Stop block or next to the
//! owner's "consolidate" prompt).
//!
//! Upstream consolidates with a configured LLM provider
//! (`ai_memory_consolidate::consolidator`, `memory_consolidate`), which
//! Cadex never has (ADR 0028). For the same result, the agent gets
//! upstream's own instructions: `BATCH_SYSTEM_PROMPT` (public in the crate,
//! so it follows upstream's updates) up to its JSON output contract, and
//! the path/tier/kind conventions of `batch_request_plan` (private there,
//! copied below from consolidator.rs at fa0ec25, 2026-11-16; unchanged at
//! v3.5.0, 411d90d). In place of
//! the JSON reply, the agent writes the same pages with the memory tools
//! (`memory_write_pages_batch`, `memory_write_page`), which do what the
//! consolidator's write does (supersession, git commit).

use std::collections::HashMap;

use ai_memory_consolidate::consolidator::BATCH_SYSTEM_PROMPT;
use axum::extract::Query;
use axum::http::StatusCode;
use axum::response::IntoResponse;

/// From `batch_request_plan` (consolidator.rs, fa0ec25): where each kind of
/// page goes and the two fields every page carries.
const CONVENTIONS: &str = "\
## Where the pages go (ai-memory's conventions)
- sessions/<session_id>.md  (tier episodic, kind fact: this session's narrative; it exists \
already as a draft from the capture: replace it)
- concepts/<slug>.md         (semantic, evergreen concept pages)
- decisions/<short>.md       (semantic, ADR-style records; kind decision)
- gotchas/<slug>.md          (semantic, failure modes / surprises; kind gotcha)
- _slots/<name>.md           (pinned memory slot; use sparingly)
- tier is exactly one of: working | episodic | semantic | procedural.
- kind is exactly one of: decision | gotcha | rule | fact. A `rule` is written as a clear \
standalone instruction; the system routes it to `_rules/<slug>.md` and the lint pass suggests \
copying it into the project's CLAUDE.md.
- entities: up to 10 short lowercase names the page is about (technologies, components, files); \
`[]` when none.
";

fn reason_line(reason: &str) -> &'static str {
    match reason {
        "context" => "Cadex: this session's context is filling up.",
        "ready" => "Cadex: the owner marked this task as ready for review.",
        _ => "Cadex: the owner asked to consolidate this session into the project memory.",
    }
}

/// The whole request for `session_id`, in `scope` (workspace, project)
/// when the folder names one: `memory_write_pages_batch` takes no default
/// scope (real test, 2026-11-16: Haiku stopped for want of a workspace).
pub(crate) fn text(session_id: &str, reason: &str, scope: Option<(String, String)>) -> String {
    let scope_line = scope.map_or_else(String::new, |(workspace, project)| {
        format!("- This project's memory is workspace `{workspace}`, project `{project}`: pass both to every write tool.\n")
    });
    let rules = BATCH_SYSTEM_PROMPT.split("\n## Output\n").next().unwrap_or(BATCH_SYSTEM_PROMPT);
    format!(
        "{line} Consolidate this session into the project memory now, following ai-memory's \
consolidation rules below, then stop. Do this once; it is not a new task for the code.\n\n\
{rules}\n\n{CONVENTIONS}\n\
## How to do it here\n\
- The session to consolidate is this conversation (session id `{session_id}`). When your \
context has lost detail (a compaction), read its captured observations with \
`memory_read_session_observations` (session_id `{session_id}`, order asc).\n\
- If the project has a `_prompts/consolidation.md` page (`memory_read_page`), apply it as the \
optional project preferences described above.\n\
- Before writing a durable page, search with `memory_query`: update an existing page \
(`memory_patch_page` or a new version at the same path) instead of creating a near duplicate.\n\
{scope_line}\
- Write 1-5 pages with `memory_write_pages_batch` (or `memory_write_page` for one), with the \
fields above (path, title, body, tier, kind, tags, entities, summary).\n\
- Then reply in one short line with the paths you wrote, and stop.\n",
        line = reason_line(reason),
    )
}

/// The route: plain text, as `/handoff` and `/recap` answer.
pub(crate) async fn handle(Query(query): Query<HashMap<String, String>>) -> impl IntoResponse {
    let Some(session_id) = query.get("session_id").filter(|s| !s.is_empty() && s.len() <= 128) else {
        return (StatusCode::BAD_REQUEST, "session_id is required".to_string());
    };
    let reason = query.get("reason").map_or("asked", String::as_str);
    let workspace = query.get("workspace").map(String::as_str).filter(|w| !w.is_empty());
    let scope = query.get("cwd").and_then(|cwd| crate::mcp_scope::scope_of(cwd, workspace));
    (StatusCode::OK, text(session_id, reason, scope))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upstreams_rules_without_its_json_contract_and_with_the_tools() {
        let text = text("s-1", "context", Some(("default".into(), "acme".into())));
        assert!(text.contains("workspace `default`, project `acme`"));
        assert!(!super::text("s-1", "asked", None).contains("workspace `"));
        assert!(text.starts_with("Cadex: this session's context is filling up."));
        assert!(text.contains("## FAITHFULNESS"), "upstream's rules are in");
        assert!(text.contains("## SECURITY BOUNDARY"));
        assert!(!text.contains("ConsolidatedBatch JSON"), "upstream's JSON output contract is out");
        assert!(!text.contains("{{wikilinks}}"));
        assert!(text.contains("sessions/<session_id>.md") && text.contains("`s-1`"));
        assert!(text.contains("memory_write_pages_batch"));
        assert!(BATCH_SYSTEM_PROMPT.contains("\n## Output\n"), "upstream renamed its output heading: update the split");
    }
}
