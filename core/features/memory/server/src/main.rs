//! `cadex-memory`: ai-memory's engine (hook ingest, briefing, MCP tools)
//! served on a Unix domain socket for the Cadex app.
//!
//! What upstream `ai-memory serve` does and this process leaves out: the TCP
//! listener, the web UI and API, multi-user auth (single local user, open
//! access on a 0600 socket), remote LLM providers, the consolidation and
//! profile workers that need a model, and the clock-driven maintenance
//! scheduler.

use std::path::PathBuf;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};

mod engine;
mod lazy_embedder;
mod transcripts;

/// Command-line options. Parsed by hand to keep `clap` out of the binary.
pub(crate) struct Args {
    pub(crate) socket: PathBuf,
    pub(crate) data_dir: PathBuf,
    pub(crate) embeddings: bool,
    pub(crate) watcher: bool,
    pub(crate) embed_idle: Duration,
}

fn parse_args() -> Result<Args> {
    let mut socket = None;
    let mut data_dir = None;
    let mut embeddings = true;
    let mut watcher = true;
    let mut embed_idle = Duration::from_secs(60);
    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--socket" => socket = it.next().map(PathBuf::from),
            "--data-dir" => data_dir = it.next().map(PathBuf::from),
            "--no-embeddings" => embeddings = false,
            "--no-watcher" => watcher = false,
            "--embed-idle-secs" => {
                let secs: u64 = it.next().context("--embed-idle-secs needs a value")?.parse()?;
                embed_idle = Duration::from_secs(secs);
            }
            "--version" => {
                println!("cadex-memory {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            other => bail!("unknown argument {other}"),
        }
    }
    Ok(Args {
        socket: socket.context("--socket <path> is required")?,
        data_dir: data_dir.context("--data-dir <path> is required")?,
        embeddings,
        watcher,
        embed_idle,
    })
}

fn main() -> Result<()> {
    let started = Instant::now();
    let argv: Vec<String> = std::env::args().skip(1).collect();
    if argv.first().map(String::as_str) == Some("scan-transcripts") {
        return transcripts::run(&argv[1..]);
    }
    let args = parse_args()?;
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
    runtime.block_on(engine::run(args, started))
}
