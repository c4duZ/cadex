//! Plan 40 A2: the seed's queues (tests/panel/seed.rs): the inbox, the
//! workstream run and the pending auto-improve proposals.

use ai_memory_core::{
    ActorContext, AgentKind, AuthLevel, MessageClaim, MessageNature, NewAgentMessage,
    NewWorkstreamEvent, PagePath, ProjectId, Sanitizer, WorkspaceId, WorkstreamEventKind,
};
use ai_memory_store::{
    AutoImproveProposalOperation, FinishWorkstreamRun, ManagedRunAuthority,
    NewAutoImproveProposal, PrepareWorkstreamRun, StageAutoImproveRun, Store,
    WorkstreamSelection,
};
use ai_memory_wiki::Wiki;

use super::{S_OPEN, WORKSTREAM_NAME, session_id};

/// Through `Wiki::send_agent_message`, what the panel's own POST /messages
/// calls after its browser checks; then one popped, as an agent collects it.
pub(super) async fn seed_inbox(store: &Store, wiki: &Wiki, ws: WorkspaceId, main: ProjectId, site: ProjectId) -> anyhow::Result<()> {
    let mail = [
        (site, "Collected request", "Please review the deploy notes."),
        (main, "Panel question", "Should the inbox show collected mail?"),
        (site, "Site needs the engine doc", "Link the engine decision from the site."),
    ];
    for (from, subject, body) in mail {
        let message = NewAgentMessage {
            from_workspace_id: ws,
            from_project_id: from,
            from_agent: AgentKind::ClaudeCode,
            from_session_id: None,
            from_owner_user: None,
            to_workspace_id: ws,
            to_project_id: main,
            to_agent: Some(AgentKind::ClaudeCode),
            subject: Some(subject.into()),
            body: body.into(),
            nature: MessageNature::Unknown,
            evidence: None,
        };
        wiki.send_agent_message(message, ActorContext::anonymous()).await?;
    }
    let claim = MessageClaim {
        workspace_id: ws,
        project_id: main,
        claiming_agent: AgentKind::ClaudeCode,
        claiming_session: Some(session_id(S_OPEN)),
        claiming_user: None,
    };
    let popped = store.writer.pop_message(claim, None).await?;
    anyhow::ensure!(popped.is_some(), "the seed's first message was not collected");
    Ok(())
}

pub(super) async fn seed_workstream(store: &Store, ws: WorkspaceId, main: ProjectId) -> anyhow::Result<()> {
    let run = store.writer.prepare_workstream_run(PrepareWorkstreamRun {
        scope_by_id: false,
        workspace_id: ws,
        project_id: main,
        repo_fingerprint: "seed-repo".into(),
        worktree_fingerprint: "seed-tree".into(),
        cwd: "/seed/cadex".into(),
        agent: AgentKind::ClaudeCode,
        automatic_harness: false,
        available_agents: Vec::new(),
        selection: WorkstreamSelection::New(WORKSTREAM_NAME.into()),
        lease_owner: "seed-lease".into(),
    }).await?;
    let authority = ManagedRunAuthority::from_auth(AuthLevel::Root, None, None, &ActorContext::anonymous(), false);
    store.writer.finish_workstream_run(authority, FinishWorkstreamRun {
        sanitizer: Sanitizer::default(),
        run_id: run.run_id,
        native_session_id: Some("seed-native-session".into()),
        source_cursor: Some("seed-cursor".into()),
        events: vec![NewWorkstreamEvent {
            event_id: "seed-event-1".into(),
            agent: run.agent,
            native_session_id: "seed-native-session".into(),
            source_record_id: None,
            kind: WorkstreamEventKind::Message,
            role: Some("assistant".into()),
            content: "Seed run finished the overview.".into(),
            occurred_at: Some("2026-11-01T16:00:00Z".into()),
            metadata: serde_json::json!({}),
        }],
        complete: true,
        segment_path: None,
        exit_code: Some(0),
    }).await?;
    Ok(())
}

/// One staged auto-improve run with a `create` proposal per path.
pub(super) async fn seed_proposals(store: &Store, ws: WorkspaceId, project: ProjectId, paths: &[&str]) -> anyhow::Result<()> {
    let proposals = paths.iter().map(|path| NewAutoImproveProposal {
        operation: AutoImproveProposalOperation::Create,
        target_path: PagePath::new(*path).expect("seed proposal path"),
        kind: "note".into(),
        title: format!("Proposal {path}"),
        confidence: 0.8,
        rationale: format!("The sessions keep repeating {path}."),
        evidence_json: serde_json::json!([{"source": "seed"}]),
        body_markdown: format!("# Proposal {path}\n\nproposed body"),
        artifact_sha256: None,
        edit_mode: None,
        patch_json: None,
        expected_base_body_sha256: None,
    }).collect();
    store.writer.stage_auto_improve_run(StageAutoImproveRun {
        workspace_id: ws,
        project_id: project,
        session_id: None,
        provider: Some("seed".into()),
        model: Some("seed-model".into()),
        summary: Some("seed auto-improve run".into()),
        warnings_json: serde_json::json!([]),
        rejected_candidates_json: serde_json::json!([]),
        config_json: serde_json::json!({"mode": "stage"}),
        proposal_actor: ActorContext { agent: Some("auto_improve".into()), ..ActorContext::default() },
        proposals,
    }).await?;
    Ok(())
}
