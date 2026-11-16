//! "Organize History with AI" (memory.bootstrap; plan 22 phase G: "o
//! `claude -p` lê o que o backfill importou e escreve as páginas de
//! decisões, armadilhas e conceitos", the owner, 2026-11-15): upstream's
//! bootstrap engine (`Bootstrap::process_sources`: budget prune, chunks,
//! durable per-chunk progress, the `bootstrap.md` manifest, one atomic
//! write) fed with the project's sessions instead of its git log and docs.
//!
//! Each ended session of the project becomes one source: its prompts, the
//! files its edits named, its tools and its last assistant message
//! (session_facts.rs, the handoff's facts). Upstream drops sources over its
//! 150k-token cap (its CLI default) from the front, so the oldest go first.
//!
//! Only on the owner's click, after the estimate (`dry_run`), and even with
//! the background agent off (ADR 0029), within the same budgets. A run cut
//! by the daily budget keeps its finished chunks (upstream's `resume`), and
//! the next click goes on from there. A project bootstrapped once refuses a
//! second run (upstream's manifest check).

use std::sync::Arc;

use ai_memory_consolidate::{Bootstrap, BootstrapConfig, BootstrapError, BootstrapSource, DEFAULT_CHUNK_INPUT_TOKENS, SourceKind};
use ai_memory_core::{OwnerFilter, ProjectId, WorkspaceId};
use ai_memory_llm::{ChatRequest, ChatResponse, LlmError, LlmProvider, LlmResult};
use async_trait::async_trait;
use serde::Serialize;
use tracing::{info, warn};

use super::Ctx;
use super::jobs::Step;
use super::queue::Scope;
use crate::session_facts::Facts;

/// Upstream's bootstrap CLI default for `--max-input-tokens`.
const MAX_INPUT_TOKENS: usize = 150_000;
/// Upstream's output cap per chunk (`bootstrap_chunk_max_tokens` with
/// chunking on, bootstrap.rs at fa0ec25: private, so repeated here).
const CHUNK_MAX_OUTPUT_TOKENS: f64 = 16_000.0;
/// The system prompt and chunk scaffolding per call, rounded up.
const CALL_OVERHEAD_TOKENS: f64 = 4_000.0;
/// Upstream's chars/4 estimate undercounts dense text by ~40% (its #884).
const UNDERCOUNT: f64 = 1.4;
/// The price used for the estimate, US$ per million tokens (input, output).
/// Claude Haiku 4.5: $1 input, $5 output; input priced at the 1.25×
/// cache-write rate, since `claude -p` writes the prompt to the cache. The
/// newer Haiku 5.5 costs less ($0.10/$0.50 up to 100k-token prompts), so
/// whichever "haiku" resolves to, the estimate does not come in low. Source:
/// Anthropic's model pricing table (claude-api reference cached 2026-11-03),
/// read 2026-11-16.
pub(crate) const HAIKU_USD_PER_MTOK: (f64, f64) = (1.25, 5.0);

/// What the dry run answers.
#[derive(Debug, Serialize)]
pub(crate) struct Estimate {
    pub(crate) estimate_usd: f64,
    pub(crate) sessions: usize,
    pub(crate) observations: u64,
    pub(crate) calls: usize,
    pub(crate) input_tokens: u64,
    pub(crate) output_tokens: u64,
}

/// The estimate's formula: every call at its full output cap, the input
/// with the undercount and the per-call overhead, at `HAIKU_USD_PER_MTOK`.
pub(crate) fn cost(estimated_input_tokens: usize, calls: usize) -> (f64, u64, u64) {
    let input = estimated_input_tokens as f64 * UNDERCOUNT + calls as f64 * CALL_OVERHEAD_TOKENS;
    let output = calls as f64 * CHUNK_MAX_OUTPUT_TOKENS;
    let usd = (input * HAIKU_USD_PER_MTOK.0 + output * HAIKU_USD_PER_MTOK.1) / 1_000_000.0;
    // Rounded up to the cent; the epsilon keeps 0.12 from becoming 0.13.
    (((usd * 100.0) - 1e-6).ceil().max(0.0) / 100.0, input.ceil() as u64, output as u64)
}

/// The dry run never calls a model; upstream's type still wants one.
struct NoCall;

#[async_trait]
impl LlmProvider for NoCall {
    fn name(&self) -> &'static str {
        "none"
    }
    fn model(&self) -> &str {
        "none"
    }
    async fn complete(&self, _: ChatRequest) -> LlmResult<ChatResponse> {
        Err(LlmError::NotConfigured("dry run".into()))
    }
    async fn complete_structured_raw(&self, _: ChatRequest, _: serde_json::Value) -> LlmResult<serde_json::Value> {
        Err(LlmError::NotConfigured("dry run".into()))
    }
}

/// The project's scope ids by name; `None` when the memory has none.
async fn ids(ctx: &Ctx, scope: &Scope) -> Option<(WorkspaceId, ProjectId)> {
    let scopes = ctx.reader.list_all_scopes().await.ok()?;
    scopes.into_iter().find(|s| s.workspace_name == scope.workspace && s.project_name == scope.project).map(|s| (s.workspace_id, s.project_id))
}

/// One session as a bootstrap source.
fn source_text(id: &str, started: &str, ended: &str, facts: &Facts) -> String {
    let mut text = format!("Session {id}, {started} to {ended}.\n");
    if !facts.prompts.is_empty() {
        text.push_str("Prompts:\n");
        for prompt in &facts.prompts {
            text.push_str(&format!("- {}\n", prompt.replace('\n', " ")));
        }
    }
    if !facts.edited.is_empty() {
        text.push_str(&format!("Files edited: {}\n", facts.edited.join(", ")));
    }
    if !facts.tools.is_empty() {
        let tools: Vec<String> = facts.tools.iter().map(|(name, n)| format!("{name} ×{n}")).collect();
        text.push_str(&format!("Tools: {}\n", tools.join(", ")));
    }
    if let Some(last) = &facts.last_assistant {
        text.push_str(&format!("Last assistant message: {last}\n"));
    }
    text
}

/// The project's ended sessions as sources, oldest first: (sources, sessions, observations).
async fn sources(ctx: &Ctx, ws: WorkspaceId, proj: ProjectId) -> anyhow::Result<(Vec<BootstrapSource>, usize, u64)> {
    let mut sessions = ctx.reader.sessions_for_scope(ws, proj, OwnerFilter::Any, false, 2_000, 0).await?;
    sessions.sort_by(|a, b| a.started_at.cmp(&b.started_at));
    let observations = sessions.iter().map(|s| s.observation_count).sum();
    let mut out = Vec::with_capacity(sessions.len());
    for s in &sessions {
        let facts = Facts::load(&ctx.reader, ws, proj, s.session_id).await?;
        if facts.prompts.is_empty() && facts.edited.is_empty() {
            continue;
        }
        let id = s.session_id.to_string();
        let ended = s.ended_at.as_deref().unwrap_or("?");
        out.push(BootstrapSource { kind: SourceKind::DocFile, label: format!("session {id}"), text: source_text(&id, &s.started_at, ended, &facts) });
    }
    Ok((out, sessions.len(), observations))
}

fn bootstrap_config(scope: &Scope, ws: WorkspaceId, proj: ProjectId, dry_run: bool) -> BootstrapConfig {
    BootstrapConfig {
        repo_path: scope.root.clone().unwrap_or_default(),
        workspace_id: ws,
        project_id: proj,
        max_input_tokens: MAX_INPUT_TOKENS,
        chunk_input_tokens: DEFAULT_CHUNK_INPUT_TOKENS,
        sources_collected: None,
        include_git: false,
        include_readme: false,
        include_docs: false,
        include_code: false,
        since: None,
        dry_run,
        force: false,
        resume: true,
    }
}

/// The dry run: what a run would send and cost, without a call.
pub(crate) async fn estimate(ctx: &Ctx, scope: &Scope) -> Result<Estimate, String> {
    let Some((ws, proj)) = ids(ctx, scope).await else { return Err("this project has no memory yet".into()) };
    let (sources, sessions, observations) = sources(ctx, ws, proj).await.map_err(|e| format!("{e:#}"))?;
    let empty = Estimate { estimate_usd: 0.0, sessions, observations, calls: 0, input_tokens: 0, output_tokens: 0 };
    if sources.is_empty() {
        return Ok(empty);
    }
    let runner = Bootstrap { reader: ctx.reader.clone(), wiki: ctx.wiki.clone(), llm: Arc::new(NoCall), writer: ctx.writer.clone() };
    match runner.process_sources(&bootstrap_config(scope, ws, proj, true), sources).await {
        Ok(plan) => {
            let (estimate_usd, input_tokens, output_tokens) = cost(plan.estimated_input_tokens, plan.llm_chunks);
            Ok(Estimate { estimate_usd, calls: plan.llm_chunks, input_tokens, output_tokens, ..empty })
        }
        Err(BootstrapError::NoSources) => Ok(empty),
        Err(error) => Err(error.to_string()),
    }
}

/// The run the owner asked for.
pub(crate) async fn run(step: &Step<'_>) {
    let ctx = step.ctx;
    let scope = &step.job.scope;
    let Some((ws, proj)) = ids(ctx, scope).await else {
        return step.note("bootstrap", false, "project not in the memory");
    };
    let sources = match sources(ctx, ws, proj).await {
        Ok((sources, _, _)) if !sources.is_empty() => sources,
        Ok(_) => return step.note("bootstrap", true, "no session to organize"),
        Err(error) => return warn!(error = %format!("{error:#}"), "bootstrap sources unreadable"),
    };
    let llm = step.provider("bootstrap");
    let runner = Bootstrap { reader: ctx.reader.clone(), wiki: ctx.wiki.clone(), llm: llm.clone(), writer: ctx.writer.clone() };
    match runner.process_sources(&bootstrap_config(scope, ws, proj, false), sources).await {
        Ok(outcome) => info!(pages = outcome.pages_written.len(), chunks = outcome.llm_chunks, "memory agent bootstrap wrote the pages"),
        Err(BootstrapError::AlreadyBootstrapped) => step.note("bootstrap", false, "already organized (bootstrap.md exists)"),
        Err(error) => warn!(%error, calls = llm.spent().0, "memory agent bootstrap stopped; the next run resumes"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_estimate_assumes_every_output_cap_is_spent() {
        // 20k estimated tokens in one chunk: 28k + 4k in at $1.25, 16k out at $5.
        let (usd, input, output) = cost(20_000, 1);
        assert_eq!((input, output), (32_000, 16_000));
        assert!((usd - 0.12).abs() < 1e-9, "{usd}");
        assert_eq!(cost(0, 0).0, 0.0);
    }
}
