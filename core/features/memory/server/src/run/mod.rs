//! `cadex-memory run [launcher flags] [harness] [native args...]`: upstream's
//! managed cross-harness launcher (`ai-memory run`,
//! crates/ai-memory-cli/src/commands/run.rs at fa0ec25, compared again at v3.5.0 = 411d90d, docs/
//! managed-workstreams.md) against the Cadex engine on memory.sock. It opens
//! a lease-backed run in the checkout's workstream, resumes the native
//! session the workstream links (or adopts or starts one), hands a harness
//! switch the previous agent's dossier, runs the agent with the terminal,
//! and afterwards imports its transcript as the workstream's ledger and
//! closes the run. Plan 22 phase E, 2026-11-16.
//!
//! The cli crate is not a library, so the launcher's own code is copied
//! where it is kept close to upstream (each module's header lists what);
//! the harness logic is the ai-memory-workstream crate's, used as is.
//!
//! - `args.rs`, `choice.rs`, `wrapper.rs`: the command line (upstream's
//!   `RunArgs`, harness names, wrapper flags typed after the harness) and
//!   the kit's environment;
//! - `profiles.rs`, `child_env.rs`: upstream's `[run]` config (read only),
//!   `--profile`/`--env-file`/`--env`, executables on the launch `PATH`;
//! - `local.rs`, `auto.rs`, `opencode.rs`: the launch resolved before the
//!   engine (automatic harness, Kiro engine, OpenCode dialect);
//! - `uds_http.rs`, `server.rs`: HTTP over memory.sock, engine start,
//!   prepare/lease, heartbeat, cancel, finish;
//! - `flow.rs`, `launch.rs`, `adopt.rs`, `picker.rs`, `attach.rs`,
//!   `harness_ctx.rs`, `plan.rs`, `store_record.rs`, `history.rs`: one run,
//!   the plan, session adoption, Claude background attach, the Crush/Grok
//!   context packet, the store record, the dossier;
//! - `after.rs`, `import.rs`, `ledger_capture.rs`, `hookless.rs`: after the
//!   child: transcript import, finish, hookless session end;
//! - `offline.rs`, `journal.rs`, `recover.rs`: the degraded launch without
//!   the engine and its recovery on the next run;
//! - `yolo.rs`, `jail.rs`, `jail_checklist.rs`, `jail_exec.rs`,
//!   `jail_folders.rs`, `jail_choices.rs`: `--yolo` and ai-jail;
//! - `exit_prompt.rs`: the post-run menu.
//!
//! Not ported (2026-11-16):
//! - autowire (`run_autowire.rs`): it writes hooks and MCP into the agents'
//!   own config homes; Cadex never writes the owner's agent config, its
//!   session kit wires Claude (hooks, MCP) and Codex (MCP). `--no-autowire`
//!   is accepted and ignored;
//! - the project-split repair (`run_project_split.rs`) and the client
//!   project registry (`project_registry::project_binding`,
//!   `record_project_binding`, `record_prepared_checkout`): a split comes
//!   from routing a checkout by its git-remote identity on a shared server
//!   (the name changes when the remote arrives); Cadex's single local engine
//!   names a project by its marker or main repository root and the launcher
//!   sends no remote identity, so no split can arise, and `--project-id` is
//!   passed through per launch without being remembered;
//! - `managed_project::choose` (the interactive pick among same-named
//!   projects on a multi-user server) and the manifest warning;
//! - the interactive folder picker of the ai-jail checklist (crossterm TUI).
use std::ffi::OsString;
use std::path::Path;

mod adopt;
mod after;
mod args;
mod attach;
mod auto;
mod child_env;
mod choice;
mod exit_prompt;
mod flow;
mod harness_ctx;
mod history;
mod hookless;
mod import;
mod jail;
mod jail_checklist;
mod jail_choices;
mod jail_exec;
mod jail_folders;
mod journal;
mod launch;
mod ledger_capture;
mod local;
mod offline;
mod opencode;
mod picker;
mod plan;
mod profiles;
mod recover;
mod server;
mod store_record;
mod uds_http;
mod wrapper;
mod yolo;

/// Text from a transcript or the engine, safe to print on a terminal (no
/// escape sequences), as upstream's `show::terminal_text`.
pub(crate) fn terminal_text(text: &str) -> String {
    text.chars().map(|c| if c.is_control() && c != '\n' && c != '\t' { '\u{FFFD}' } else { c }).collect()
}

/// `(workspace, project)` as the hooks name them: the account's workspace,
/// else the marker's, else `default`; the marker's project, else the main
/// repository root's name (mcp_scope.rs). Outside a repository with no
/// marker, the folder's own name (upstream's directory fallback).
pub(crate) fn scope(cwd: &Path, account_workspace: Option<&str>) -> (String, String) {
    let text = cwd.to_string_lossy();
    if let Some(scope) = crate::mcp_scope::scope_of(&text, account_workspace) {
        return scope;
    }
    let workspace = account_workspace.unwrap_or(ai_memory_core::DEFAULT_WORKSPACE_NAME).to_owned();
    let project = cwd.file_name().and_then(|n| n.to_str()).filter(|n| !n.is_empty()).unwrap_or("root").to_owned();
    (workspace, project)
}

/// Run the launcher; the child's exit code, or 1 when the launcher failed
/// (the error is printed).
pub(crate) fn main(argv: &[OsString]) -> i32 {
    let outcome = args::parse(argv).and_then(|parsed| {
        let env = args::env(&parsed)?;
        let settings = profiles::load();
        if let Some(error) = &settings.load_error && parsed.profile.is_none() {
            eprintln!("ai-memory: ignoring the ai-memory config's [run] settings: {}", terminal_text(error));
        }
        // Two workers, as the engine: the launcher waits on one child and
        // one socket.
        let runtime = tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build()?;
        let code = runtime.block_on(exit_prompt::run_with_exit_prompt(parsed, &env, &settings));
        runtime.shutdown_timeout(std::time::Duration::from_millis(200));
        code
    });
    match outcome {
        Ok(code) => code,
        Err(error) => {
            eprintln!("cadex-memory run: {}", terminal_text(&format!("{error:#}")));
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_text_drops_escape_sequences() {
        assert_eq!(terminal_text("a\x1b[2Jb\nc"), "a\u{FFFD}[2Jb\nc");
    }

    #[test]
    fn a_folder_outside_a_repository_is_its_own_project() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("loose");
        std::fs::create_dir_all(&dir).unwrap();
        assert_eq!(scope(&dir, Some("acct")), ("acct".into(), "loose".into()));
    }
}
