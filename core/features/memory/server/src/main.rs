//! `cadex-memory`: ai-memory's engine (hook ingest, briefing, MCP tools)
//! served on a Unix domain socket for the Cadex app.
//!
//! What upstream `ai-memory serve` does and this process leaves out: the TCP
//! listener, the web UI and API, multi-user auth (one local user; the socket
//! is 0600 and takes Cadex session tokens instead), remote LLM providers,
//! the consolidation and profile workers that need a model, and the
//! clock-driven maintenance scheduler. What it adds: it leaves when the
//! last agent session ends and restarts itself to give memory back after
//! the embedding model unloads (plan 22, phase C).

use std::time::Instant;

use anyhow::Result;

mod args;
mod auth;
mod engine;
mod lazy_embedder;
mod restart;
mod serve;
mod sessions;
mod spool;
mod sys;
mod transcripts;

fn main() -> Result<()> {
    let started = Instant::now();
    let argv: Vec<String> = std::env::args().skip(1).collect();
    match argv.first().map(String::as_str) {
        Some("scan-transcripts") => return transcripts::run(&argv[1..]),
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
    // Few threads: the engine serves one person's sessions, and every idle
    // worker thread is RSS and wakeups for nothing.
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()?;
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
