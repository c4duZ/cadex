//! `cadex-memory`: ai-memory's engine (hook ingest, briefing, MCP tools)
//! served on a Unix domain socket for the Cadex app.
//!
//! What upstream `ai-memory serve` does and this process leaves out: the TCP
//! listener, the web UI and API, multi-user auth (one local user; the socket
//! is 0600 and takes Cadex session tokens instead), remote LLM providers,
//! the consolidation and profile workers that need a model, and the
//! clock-driven maintenance scheduler. What it adds: it leaves when the
//! last agent session ends and restarts itself to give memory back after
//! the embedding model unloads, and it learns the project's past sessions and
//! the ones that ran outside Cadex from their transcripts (plan 22, phase C).
//! `cadex-memory run` is upstream's managed launcher for Claude Code and
//! Codex against this engine (run/mod.rs, plan 22 phase E).

use std::time::Instant;

use anyhow::Result;

mod accounts;
mod agent;
mod args;
mod auth;
mod auto_index;
mod auto_watch;
mod auto_wiki;
mod capture;
mod consolidate_prompt;
#[cfg(debug_assertions)]
mod debug_panic;
mod engine;
mod file_claim;
mod handoff;
mod hook_body;
mod import;
mod import_jobs;
mod import_state;
mod lazy_embedder;
mod maintenance;
mod maintenance_jobs;
mod maintenance_state;
mod marker;
mod model_fetch;
mod marker_query;
mod mcp_scope;
mod plugin;
mod project_key;
mod project_paths;
mod replay;
mod replay_capture;
mod restart;
mod run;
mod serve;
mod session_facts;
mod sessions;
mod spool;
mod sys;
mod transcripts;

fn main() -> Result<()> {
    let started = Instant::now();
    // `run` passes the agent's arguments through untouched, so it reads them
    // as OS strings (std::env::args panics on one that is not UTF-8).
    let raw: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    if raw.first().is_some_and(|a| a == "run") {
        std::process::exit(run::main(&raw[1..]));
    }
    let argv: Vec<String> = std::env::args().skip(1).collect();
    match argv.first().map(String::as_str) {
        Some("scan-transcripts") => return transcripts::run(&argv[1..]),
        Some("export-plugin") => return plugin::run(&argv[1..]),
        Some("--version") => {
            println!("cadex-memory {}", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        _ => {}
    }
    let args = args::parse(&argv)?;
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_env("CADEX_MEMORY_LOG")
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .with_writer(std::io::stderr)
        .init();
    #[cfg(debug_assertions)]
    if debug_panic::enabled() {
        debug_panic::abort_on_panic();
    }
    // Few threads: the engine serves one person's sessions, and every idle
    // worker thread is RSS and wakeups for nothing.
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()?;
    if args.warm {
        runtime.block_on(serve::warm(&args))?;
        runtime.shutdown_timeout(std::time::Duration::from_millis(500));
        return Ok(());
    }
    let socket = args.socket.clone();
    let exit = runtime.block_on(serve::run(args, started))?;
    // Tasks still parked (the MCP sessions' timers, a model fetch) end here,
    // before the exec, rather than with a half-written file during it.
    runtime.shutdown_timeout(std::time::Duration::from_millis(500));
    if let serve::Exit::Restart { sessions, lock, listener } = exit {
        let error = restart::exec(&sessions, &lock, &listener);
        tracing::error!(%error, "restart failed; cadex-memory exits");
        let _ = std::fs::remove_file(socket);
        return Err(error);
    }
    Ok(())
}
