//! What each memory agent job runs (plan 22 phase G, 2026-11-16), with
//! upstream's public functions and a `ClaudeProvider` per step:
//!
//! - a live SessionEnd: the session's consolidation by upstream's SessionEnd
//!   worker path (`Consolidator::consolidate_session_keeping_agent_page`,
//!   serve.rs `run_session_consolidation_worker`: the single-page mode, not
//!   the batch one), then upstream's profile pass (its worker runs one after
//!   every SessionEnd), then auto-improve and experience for the project
//!   (improve.rs), then, with no session live and the Mac idle 10 min, a
//!   dream;
//! - after a compaction: the same consolidation of the session so far;
//! - neither for a session with no prompt and no tool (upstream's own test;
//!   plan 35 C): a ledger line with no cost and nothing else;
//! - dream (dream.rs) and bootstrap (bootstrap.rs).
//!
//! **The "already consolidated in the session" rule is upstream's own:** a
//! session page whose frontmatter says `consolidated_by: agent` is kept.
//! The memory tools stamp it when the session's own Claude writes
//! `sessions/<id>.md` (`stamp_session_page` in ai-memory-mcp), which is what
//! Cadex's in-session consolidation (consolidate_prompt.rs, the Stop block)
//! makes it do. The consolidator checks it before the call (so a kept page
//! costs nothing) and again at the write, which is conditional on the page
//! version it read: a page the agent writes while `claude -p` runs is never
//! replaced. Nothing compares timestamps.
//!
//! Every job but bootstrap needs `enabled`; every one checks the day's spend
//! first and is skipped, with a "budget" line, when one more call would pass
//! the daily budget.

use std::sync::Arc;
use std::time::{Duration, Instant};

use ai_memory_consolidate::{Consolidator, ConsolidatorError, SessionPageConsolidation, redacted_error_summary};
use ai_memory_core::{ActorContext, SessionId};
use ai_memory_llm::LlmProvider;
use tracing::{debug, info, warn};

use super::Ctx;
use super::claude_cli::Invocation;
use super::config::{self, Config};
use super::ledger::{self, Entry};
use super::provider::{ClaudeProvider, Label};
use super::queue::{Job, Kind, Queue};

/// The idle time after which a SessionEnd with no other session live sets
/// off a dream (plan 22 phase G: "computador parado").
pub(crate) const DREAM_IDLE: Duration = Duration::from_secs(600);

/// One job's settings, account and Claude Code, for its steps.
pub(crate) struct Step<'a> {
    pub(crate) ctx: &'a Ctx,
    pub(crate) cfg: Config,
    pub(crate) job: &'a Job,
    pub(crate) inv: Invocation,
    pub(crate) version: Option<String>,
}

impl Step<'_> {
    /// A provider whose calls the ledger files under `kind`.
    pub(crate) fn provider(&self, kind: &'static str) -> Arc<ClaudeProvider> {
        let label = Label {
            kind,
            workspace: self.job.scope.workspace.clone(),
            project: self.job.scope.project.clone(),
            session: self.job.session.clone(),
            trigger: None,
        };
        Arc::new(ClaudeProvider::new(self.inv.clone(), self.cfg.daily_budget_usd, self.ctx.data_dir.clone(), label, self.version.clone()))
    }

    /// A provider whose calls the ledger files under `kind` and the session
    /// they are about, with the job's own session as the `trigger` (plan 35 G:
    /// the auto-improve line named the session that ended, not the one reviewed).
    pub(crate) fn provider_about(&self, kind: &'static str, about: Option<String>) -> Arc<ClaudeProvider> {
        let label = Label {
            kind,
            workspace: self.job.scope.workspace.clone(),
            project: self.job.scope.project.clone(),
            trigger: self.job.session.clone().filter(|t| about.as_ref() != Some(t)),
            session: about,
        };
        Arc::new(ClaudeProvider::new(self.inv.clone(), self.cfg.daily_budget_usd, self.ctx.data_dir.clone(), label, self.version.clone()))
    }

    /// A ledger line with no cost about `about`, as `provider_about` files it.
    pub(crate) fn note_about(&self, kind: &str, about: Option<String>, ok: bool, error: &str) {
        ledger::append(&self.ctx.data_dir, &Entry {
            at: ledger::now(),
            kind: kind.into(),
            workspace: self.job.scope.workspace.clone(),
            project: self.job.scope.project.clone(),
            trigger: self.job.session.clone().filter(|t| about.as_ref() != Some(t)),
            session: about,
            ok,
            error: Some(error.into()),
            claude_version: self.version.clone(),
            model: self.cfg.model.clone(),
            ..Entry::default()
        });
    }

    /// A ledger line with no cost: how a job ended without a call.
    pub(crate) fn note(&self, kind: &str, ok: bool, error: &str) {
        note(self.ctx, self.job, &self.cfg, self.version.clone(), kind, ok, error);
    }
}

fn note(ctx: &Ctx, job: &Job, cfg: &Config, version: Option<String>, kind: &str, ok: bool, error: &str) {
    ledger::append(&ctx.data_dir, &Entry {
        at: ledger::now(),
        kind: kind.into(),
        workspace: job.scope.workspace.clone(),
        project: job.scope.project.clone(),
        session: job.session.clone(),
        trigger: None,
        cost_usd: 0.0,
        ok,
        error: Some(error.into()),
        claude_version: version,
        model: cfg.model.clone(),
        call: None,
    });
}

/// Run `job` to its end (the worker calls one at a time).
pub(crate) async fn run(ctx: &Ctx, queue: &Queue, job: &Job) {
    let cfg = config::read(&ctx.data_dir);
    if job.kind != Kind::Bootstrap && !cfg.enabled {
        debug!(kind = job.kind.as_str(), "memory agent off; job dropped");
        return;
    }
    if !ledger::fits(&ctx.data_dir, cfg.call_budget_usd, cfg.daily_budget_usd) {
        info!(kind = job.kind.as_str(), "memory agent daily budget reached; job skipped");
        note(ctx, job, &cfg, None, job.kind.as_str(), false, "budget");
        return;
    }
    let Some(exe) = cfg.claude_binary(ctx.home.as_deref()) else {
        note(ctx, job, &cfg, None, job.kind.as_str(), false, "claude not found");
        return;
    };
    let account = cfg.account_for(job.scope.root.as_deref());
    let version = ctx.version_of(&exe, account.as_deref()).await;
    let inv = Invocation {
        exe,
        model: cfg.model.clone(),
        call_budget_usd: cfg.call_budget_usd,
        account,
        timeout: super::CALL_TIMEOUT,
    };
    let step = Step { ctx, cfg, job, inv, version };
    let started = Instant::now();
    if matches!(job.kind, Kind::SessionEnd | Kind::Compact) && !has_work(&step).await {
        // Upstream closes such a session with no page, handoff, consolidation or profile
        // (router.rs, `end_admitted_lifecycle_only_session`); this job went past it and spent the
        // haiku on panels opened and closed with no prompt (plan 35 C: 3cd2e5f6, d2a9e4be).
        step.note(job.kind.as_str(), true, "empty session: no prompt and no tool");
        return;
    }
    match job.kind {
        Kind::SessionEnd => {
            consolidate(&step, "consolidate").await;
            profile(&step).await;
            super::improve::run(&step).await;
            maybe_dream(ctx, queue, job);
        }
        Kind::Compact => consolidate(&step, "compact").await,
        Kind::Dream => super::dream::run(&step).await,
        Kind::Bootstrap => super::bootstrap::run(&step).await,
    }
    info!(kind = job.kind.as_str(), project = %job.scope.project, ms = started.elapsed().as_millis() as u64, "memory agent job done");
}

/// Whether the job's session did anything: a prompt or a tool, upstream's own test
/// (`session_has_substantive_observation`, the one its SessionEnd uses). A session the store
/// does not know did nothing; a store error lets the job run, as before.
async fn has_work(step: &Step<'_>) -> bool {
    let Some(session) = step.job.session.as_deref() else { return true };
    let reader = &step.ctx.reader;
    let id = SessionId::from_native(session);
    match reader.find_session_scope(id).await {
        Ok(Some((ws, proj, _))) => reader.session_has_substantive_observation(ws, proj, id).await.unwrap_or(true),
        Ok(None) => false,
        Err(_) => true,
    }
}

/// Consolidate the job's session as upstream's SessionEnd worker does.
async fn consolidate(step: &Step<'_>, kind: &'static str) {
    let Some(session) = step.job.session.as_deref() else { return };
    let ctx = step.ctx;
    let llm: Arc<dyn LlmProvider> = step.provider(kind);
    let consolidator = Consolidator::new(
        ctx.reader.clone(),
        ctx.writer.clone(),
        ctx.wiki.clone(),
        llm,
        ctx.default_scope.0,
        ctx.default_scope.1,
    );
    // One local operator: Cadex's sessions carry no owner, so upstream's
    // `session_consolidation_actor` would give the anonymous actor too.
    let id = SessionId::from_native(session);
    match consolidator.consolidate_session_keeping_agent_page(id, ActorContext::anonymous()).await {
        Ok(SessionPageConsolidation::AgentPageKept) => {
            step.note(kind, true, "kept: the session's own Claude consolidated it");
        }
        Ok(SessionPageConsolidation::Consolidated(outcome)) => info!(%session, path = %outcome.path, "memory agent consolidated the session"),
        Err(ConsolidatorError::EmptySession(_)) => debug!(%session, "nothing to consolidate"),
        Err(error) => warn!(%session, summary = %redacted_error_summary(&error), "memory agent consolidation failed"),
    }
}

/// Upstream's profile pass (serve.rs `run_profile_worker`, one pass).
async fn profile(step: &Step<'_>) {
    let ctx = step.ctx;
    let distinguishes = ctx.reader.distinguishes_operators(false).await.unwrap_or(true);
    let config = ai_memory_consolidate::profile::ProfilePassConfig {
        settings: ai_memory_core::profile::ProfileSettings::default(),
        distinguishes_operators: distinguishes,
    };
    if config.settings.effective_share(distinguishes).is_none() {
        return;
    }
    let llm: Arc<dyn LlmProvider> = step.provider("profile");
    match ai_memory_consolidate::profile::run_profile_pass(&ctx.reader, &ctx.writer, &ctx.wiki, Some(&llm), &config).await {
        Ok(report) if report.entries_written > 0 || !report.errors.is_empty() => {
            info!(written = report.entries_written, llm_calls = report.llm_calls, errors = report.errors.len(), "memory agent profile pass");
        }
        Ok(_) => {}
        Err(error) => warn!(%error, "memory agent profile pass failed"),
    }
}

/// With no session live and the owner away 10 min, queue a dream.
fn maybe_dream(ctx: &Ctx, queue: &Queue, job: &Job) {
    if !ctx.sessions.pids().is_empty() {
        return;
    }
    let idle = (ctx.idle)();
    if idle.is_none_or(|idle| idle < DREAM_IDLE) {
        return;
    }
    let dream = Job { kind: Kind::Dream, scope: job.scope.clone(), session: None, manual: false, not_before: Instant::now() };
    if queue.push(ctx, dream) {
        info!(project = %job.scope.project, "the Mac is idle and no session is live: dream queued");
    }
}
