//! Auto-improve and experience for one project, after its SessionEnd (plan
//! 22 phase G, 2026-11-16).
//!
//! **Copied code.** Origin: ai-memory fa0ec25dbe987b7574a7487ecf92f0873040c2f2
//! (v3.4.7), crates/ai-memory-consolidate/src/auto_improve_schedule.rs,
//! copied 2026-11-16: the per-scope body of `run_auto_improve_scheduler_tick`
//! → `run`, `run_scheduled_auto_improve` → `review_session`,
//! `run_scheduled_experience` → `experience`, `stage_and_apply`,
//! `scheduled_auto_improve_new_proposals` → `new_proposals`, `hex_to_sha256`
//! and `redacted_scheduler_error_summary`. Upstream's public tick walks
//! every project with one provider; the agent runs one project in that
//! project's account, and those functions are private.
//!
//! **Staging.** As upstream, a review's proposals are always staged first
//! (`stage_auto_improve_run_for_owner`: rows in `auto_improve_proposals`,
//! status `pending`, and a sidecar under the project's `_pending/` in the
//! wiki); with `require_approval` (memory.requireApproval, on by default)
//! they stay pending for the owner (listed by the store's
//! `list_pending_auto_improve_reviews`, decided by the memory tools' approve
//! and reject); off, they are approved at once as upstream's scheduler does.
//!
//! **Cadence.** Upstream reviews one session per project per hourly tick,
//! sessions at least 10 min old (so the SessionEnd consolidation lands
//! first), from a watermark set when the project is first seen (history is
//! never reviewed). Here the SessionEnd job is the tick: at most one review
//! per project per hour, stamped in `<data-dir>/agent/cadence.json` only when
//! a review called the model (a pass with nothing to review, or one upstream's
//! preflight skips, costs nothing, so it does not use the hour); no minimum
//! age, since the job consolidated the session just before. Experience: upstream's `ExperienceConfig` default (after 5 new
//! completed sessions, reading the last 10 session pages), its documented
//! example (docs/experience.md); upstream leaves it off by default.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::Duration;

use ai_memory_consolidate::auto_improve_schedule::AUTO_IMPROVE_AUTO_APPROVE_AGENT;
use ai_memory_consolidate::{
    AutoImproveError, AutoImproveReport, AutoImproveReviewConfig, ExperienceConfig, ScheduledAutoImproveSettings,
    redacted_auto_improve_summary, run_auto_improve_review, run_experience_review,
};
use ai_memory_core::{ActorContext, PagePath, ProjectId, SessionId, WorkspaceId};
use ai_memory_llm::LlmProvider;
use ai_memory_store::{
    ApproveAutoImproveProposalResult, AutoImproveProposalOperation, NewAutoImproveProposal, ReaderPool, StageAutoImproveRun,
};
use anyhow::Result;
use tracing::{info, warn};

use super::jobs::Step;
use super::provider::ClaudeProvider;
use crate::maintenance_state;

/// Upstream's `[auto_improve.scheduler] interval_secs` default.
const REVIEW_INTERVAL: Duration = Duration::from_secs(3_600);

fn cadence_file(data_dir: &Path) -> PathBuf {
    data_dir.join("agent").join("cadence.json")
}

fn last_review(data_dir: &Path, key: &str) -> Option<i64> {
    let text = std::fs::read_to_string(cadence_file(data_dir)).ok()?;
    serde_json::from_str::<HashMap<String, i64>>(&text).ok()?.get(key).copied()
}

fn stamp_review(data_dir: &Path, key: &str) {
    let mut all: HashMap<String, i64> = std::fs::read_to_string(cadence_file(data_dir))
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default();
    all.insert(key.into(), maintenance_state::now_us());
    let written = super::ledger::dir(data_dir).and_then(|_| {
        let tmp = cadence_file(data_dir).with_extension("json.tmp");
        std::fs::write(&tmp, serde_json::to_string(&all).map_err(std::io::Error::other)?)?;
        std::fs::rename(tmp, cadence_file(data_dir))
    });
    if let Err(error) = written {
        warn!(%error, "memory agent cadence not written");
    }
}

/// The scope ids of the job's session, else of its project's names.
pub(crate) async fn scope_ids(step: &Step<'_>) -> Option<(WorkspaceId, ProjectId)> {
    let reader = &step.ctx.reader;
    if let Some(session) = step.job.session.as_deref()
        && let Ok(Some((ws, proj, _))) = reader.find_session_scope(SessionId::from_native(session)).await
    {
        return Some((ws, proj));
    }
    let scopes = reader.list_all_scopes().await.ok()?;
    let scope = &step.job.scope;
    scopes
        .into_iter()
        .find(|s| s.workspace_name == scope.workspace && s.project_name == scope.project)
        .map(|s| (s.workspace_id, s.project_id))
}

struct Scoped<'a> {
    reader: &'a ReaderPool,
    step: &'a Step<'a>,
    ws: WorkspaceId,
    proj: ProjectId,
    settings: ScheduledAutoImproveSettings,
}

/// Experience when due, then one auto-improve review when due.
pub(crate) async fn run(step: &Step<'_>) {
    let Some((ws, proj)) = scope_ids(step).await else { return };
    let ctx = step.ctx;
    let settings = ScheduledAutoImproveSettings {
        review: AutoImproveReviewConfig::default(),
        require_approval: step.cfg.require_approval,
        min_session_age_secs: 0,
        max_sessions_per_tick: 1,
        experience: Some(ExperienceConfig::default()),
    };
    if let Err(error) = ctx.writer.ensure_auto_improve_scheduler_state(ws, proj).await {
        warn!(%error, "auto-improve state init failed");
        return;
    }
    let s = Scoped { reader: &ctx.reader, step, ws, proj, settings };
    if let Some(cfg) = s.settings.experience.clone()
        && let Ok((newer, _)) = ctx.reader.experience_pass_due(ws, proj).await
        && newer >= cfg.min_new_sessions
    {
        match experience(&s, &cfg).await {
            Ok(Some(staged)) => {
                if let Err(error) = ctx.writer.mark_experience_pass_run(ws, proj).await {
                    warn!(%error, "experience pass mark failed");
                }
                info!(proposals = staged, "memory agent experience pass");
            }
            Ok(None) => {}
            Err(e) => warn!(summary = %redacted_scheduler_error_summary(&e), "memory agent experience pass failed"),
        }
    }
    let key = format!("auto-improve/{}/{}", step.job.scope.workspace, step.job.scope.project);
    if !maintenance_state::is_due(last_review(&ctx.data_dir, &key), maintenance_state::now_us(), REVIEW_INTERVAL) {
        return;
    }
    let candidates = match ctx.reader.auto_improve_candidate_sessions(ws, proj, 0, s.settings.max_sessions_per_tick).await {
        Ok(candidates) => candidates,
        Err(error) => return warn!(%error, "auto-improve candidate query failed"),
    };
    for candidate in candidates {
        match ctx.writer.claim_auto_improve_scheduler_session(ws, proj, candidate.session_id, candidate.ended_at).await {
            Ok(true) => {}
            Ok(false) => continue,
            Err(error) => {
                warn!(%error, "auto-improve claim failed");
                continue;
            }
        }
        let llm = step.provider("auto-improve");
        let result = review_session(&s, &llm, candidate.session_id).await;
        // Only a review that called the model uses the project's hour: upstream's
        // preflight (too few observations, too short) skips the call.
        if llm.spent().0 > 0 {
            stamp_review(&ctx.data_dir, &key);
        }
        match result {
            Ok(staged) => info!(session = %candidate.session_id, proposals = staged, "memory agent auto-improve"),
            Err(e) => {
                let summary = redacted_scheduler_error_summary(&e);
                let _ = ctx.writer.record_auto_improve_claim_failure(ws, proj, candidate.session_id, &summary).await;
                warn!(%summary, "memory agent auto-improve failed");
            }
        }
    }
}

/// Upstream's `redacted_scheduler_error_summary` (see the origin above).
fn redacted_scheduler_error_summary(error: &anyhow::Error) -> String {
    for cause in error.chain() {
        if let Some(review_error) = cause.downcast_ref::<AutoImproveError>() {
            return redacted_auto_improve_summary(review_error);
        }
        if let Some(llm_error) = cause.downcast_ref::<ai_memory_llm::LlmError>() {
            let status = llm_error.http_status().map_or_else(|| "none".to_string(), |s| s.to_string());
            return format!("auto-improve failed: class={} status={status}", llm_error.class());
        }
    }
    "auto-improve failed: class=unrecognized status=none".to_string()
}

/// Upstream's `run_scheduled_auto_improve`: the staged proposal count.
async fn review_session(s: &Scoped<'_>, llm: &ClaudeProvider, session_id: SessionId) -> Result<usize> {
    let report = run_auto_improve_review(s.reader, llm as &dyn LlmProvider, s.ws, s.proj, session_id, s.settings.review.clone()).await?;
    stage_and_apply(s, Some(session_id), &report, "scheduler").await
}

/// Upstream's `run_scheduled_experience`; `None` on a preflight skip.
async fn experience(s: &Scoped<'_>, cfg: &ExperienceConfig) -> Result<Option<usize>> {
    let llm = s.step.provider("experience");
    let report = run_experience_review(s.reader, &*llm as &dyn LlmProvider, s.ws, s.proj, s.settings.review.clone(), cfg).await?;
    if report.provider == "none" {
        return Ok(None);
    }
    stage_and_apply(s, None, &report, "experience-scheduler").await.map(Some)
}

/// Upstream's `stage_and_apply`: stage, write the sidecars, and approve
/// unless approval is required. The staged proposal count.
async fn stage_and_apply(s: &Scoped<'_>, session_id: Option<SessionId>, report: &AutoImproveReport, trigger: &str) -> Result<usize> {
    let cfg = &s.settings.review;
    let (ctx, ws, proj) = (s.step.ctx, s.ws, s.proj);
    let proposals = new_proposals(s.reader, ws, proj, report).await?;
    let staged = ctx
        .writer
        .stage_auto_improve_run_for_owner(
            StageAutoImproveRun {
                workspace_id: ws,
                project_id: proj,
                session_id,
                provider: Some(report.provider.clone()),
                model: Some(report.model.clone()),
                summary: Some(report.summary.clone()),
                warnings_json: serde_json::to_value(&report.warnings).unwrap_or_else(|_| serde_json::json!([])),
                rejected_candidates_json: serde_json::to_value(&report.rejected_candidates).unwrap_or_else(|_| serde_json::json!([])),
                config_json: serde_json::json!({
                    "trigger": trigger,
                    "min_observations": cfg.min_observations,
                    "min_session_duration_secs": cfg.min_session_duration_secs,
                    "min_confidence": cfg.min_confidence,
                    "max_input_tokens": cfg.max_input_tokens,
                    "max_proposals_per_run": cfg.max_proposals_per_run,
                    "eval": cfg.eval,
                    "eval_results": report.eval_results(),
                    "require_approval": s.settings.require_approval,
                    "runner": "cadex-memory-agent",
                }),
                proposal_actor: ActorContext { agent: Some(cfg.proposal_actor.clone()), ..ActorContext::default() },
                proposals,
            },
            None,
        )
        .await?;
    for id in &staged.proposal_ids {
        ctx.wiki.write_auto_improve_sidecar(ws, proj, *id).await?;
    }
    if !s.settings.require_approval {
        for id in &staged.proposal_ids {
            let actor = ActorContext { agent: Some(AUTO_IMPROVE_AUTO_APPROVE_AGENT.into()), ..ActorContext::default() };
            let admission = ai_memory_wiki::AdmissionContext { op: ai_memory_wiki::AdmissionOp::WritePage, ..Default::default() };
            if let ApproveAutoImproveProposalResult::Conflict =
                ctx.wiki.approve_auto_improve_proposal(ws, proj, *id, actor, None, Some(admission)).await?
            {
                warn!(proposal = %id, "auto-improve proposal conflicted at approval");
            }
        }
    }
    for skipped in &staged.skipped {
        warn!(target_path = %skipped.target_path, reason = %skipped.reason, "auto-improve proposal was not staged");
    }
    Ok(staged.proposal_ids.len())
}

/// Upstream's `scheduled_auto_improve_new_proposals`.
async fn new_proposals(reader: &ReaderPool, ws: WorkspaceId, proj: ProjectId, report: &AutoImproveReport) -> Result<Vec<NewAutoImproveProposal>> {
    let mut proposals = Vec::with_capacity(report.proposals.len());
    for p in &report.proposals {
        let path = PagePath::new(p.path.clone())?;
        let target_exists = reader.page_body_by_ids(ws, proj, path.as_str()).await?.is_some();
        let operation = if p.edit_mode == "patch" || (target_exists && path.as_str() == "_slots/current-focus.md") {
            AutoImproveProposalOperation::Update
        } else {
            AutoImproveProposalOperation::Create
        };
        let expected_base_body_sha256 = p
            .expected_base_body_sha256
            .as_deref()
            .map(hex_to_sha256)
            .transpose()
            .map_err(|e| anyhow::anyhow!("invalid expected_base_body_sha256: {e}"))?;
        proposals.push(NewAutoImproveProposal {
            operation,
            target_path: path,
            kind: p.kind.clone(),
            title: p.title.clone(),
            confidence: f64::from(p.confidence),
            rationale: p.rationale.clone(),
            evidence_json: report.proposal_evidence_json(p)?,
            body_markdown: p.body_markdown.clone(),
            artifact_sha256: None,
            edit_mode: Some(p.edit_mode.clone()),
            patch_json: serde_json::to_value(&p.edits).ok(),
            expected_base_body_sha256,
        });
    }
    Ok(proposals)
}

/// Upstream's `hex_to_sha256`.
fn hex_to_sha256(hex: &str) -> Result<[u8; 32], String> {
    if hex.len() != 64 {
        return Err("expected 64 hex chars".into());
    }
    let mut out = [0_u8; 32];
    for (idx, chunk) in hex.as_bytes().chunks_exact(2).enumerate() {
        let s = std::str::from_utf8(chunk).map_err(|e| e.to_string())?;
        out[idx] = u8::from_str_radix(s, 16).map_err(|e| e.to_string())?;
    }
    Ok(out)
}
