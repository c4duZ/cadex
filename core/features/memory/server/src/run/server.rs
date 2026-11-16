//! The launcher's conversation with the engine's workstream router: start
//! the engine if it does not answer, prepare the run (waiting out a busy
//! lease), heartbeats, cancel after a failure and the finish.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! run.rs: `HeartbeatHealth`, `HeartbeatFailureKind`, `heartbeat_failure_notice`,
//! `heartbeat_failure_kind`, `send_managed_heartbeat_with_timeout`,
//! `cancel_managed_run_after_failure`, `prepare_managed_run` (without the
//! manifest warning, which needs a remote identity Cadex never sends),
//! `wait_out_held_lease`, `HeldLease`, `parse_held_lease`, `held_lease`,
//! `held_lease_wait`, `prepare_managed_run_with_retry`,
//! `is_active_workstream_conflict`, `active_workstream_conflict_message`,
//! `post_empty_with_retry`, `finish_with_retry`, `lease_owner` and their
//! constants. Changed for Cadex (2026-11-16): the client is uds_http.rs, no
//! i18n, and the prepare carries `?pid=<launcher pid>` so the engine
//! (sessions.rs) stays up until this launcher exits. Starting the engine is
//! Cadex's (launch.zig's `ensure`, in Rust).

use std::process::{Command, Stdio};
use std::time::Duration;

use ai_memory_core::{FinishManagedRunRequest, FinishManagedRunResponse, PrepareManagedRunRequest, PrepareManagedRunResponse};
use anyhow::{Context, Result, anyhow};
use hyper::StatusCode;
use tokio_util::sync::CancellationToken;

use super::args::Env;
use super::uds_http::{Client, ServerResponseError};

pub(crate) const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(30);
const HEARTBEAT_REQUEST_TIMEOUT: Duration = Duration::from_secs(10);
const PREPARE_BUSY_RETRY_WINDOW: Duration = Duration::from_secs(5);
const PREPARE_BUSY_RETRY_INTERVAL: Duration = Duration::from_millis(250);
/// One full server lease (90 s) plus slack, as upstream.
const HELD_LEASE_MAX_WAIT: Duration = Duration::from_secs(100);
const HELD_LEASE_EXPIRY_SLACK: Duration = Duration::from_secs(1);
/// launch.zig polls 20 ms; the SessionStart has 1 s, the launcher more: a
/// cold engine runs its migrations before it binds the socket.
const ENGINE_START_TIMEOUT: Duration = Duration::from_secs(5);

/// Answer on `/healthz`, starting the engine if nothing does (stdio to
/// /dev/null, its own session, as launch.zig): `CADEX_MEMORY_BIN` when the
/// kit names one (as the hook client), else this same binary. An engine
/// that exits before answering failed to start: no need to wait it out.
pub(crate) async fn ensure_engine(client: &Client, env: &Env) -> Result<()> {
    if client.healthy().await {
        return Ok(());
    }
    let exe = match std::env::var_os("CADEX_MEMORY_BIN").filter(|v| !v.is_empty()) {
        Some(bin) => std::path::PathBuf::from(bin),
        None => std::env::current_exe().context("locating cadex-memory to start the engine")?,
    };
    let mut command = Command::new(exe);
    command.arg("--socket").arg(&env.socket).arg("--data-dir").arg(&env.data_dir);
    if let Some(dir) = &env.tokens_dir {
        command.arg("--tokens-dir").arg(dir);
    }
    command.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    crate::sys::new_session_on_spawn(&mut command);
    let mut child = command.spawn().context("starting the memory engine")?;
    let deadline = tokio::time::Instant::now() + ENGINE_START_TIMEOUT;
    while tokio::time::Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(20)).await;
        if client.healthy().await {
            return Ok(());
        }
        if let Ok(Some(status)) = child.try_wait() {
            // Another engine may have won the lock and be binding now.
            if client.healthy().await {
                return Ok(());
            }
            return Err(anyhow!("the memory engine exited ({status}) before answering on {}", env.socket.display()));
        }
    }
    Err(anyhow!("the memory engine did not answer on {} within {}s", env.socket.display(), ENGINE_START_TIMEOUT.as_secs()))
}

pub(crate) fn lease_owner() -> String {
    let host = crate::sys::host_name().or_else(|| std::env::var("HOSTNAME").ok()).filter(|v| !v.trim().is_empty());
    format!("{}:{}", host.as_deref().unwrap_or("localhost"), std::process::id())
}

fn prepare_path() -> String {
    format!("/workstream/runs?pid={}", std::process::id())
}

fn active_workstream_conflict_message(error: &anyhow::Error) -> Option<String> {
    let response = error.downcast_ref::<ServerResponseError>()?;
    if response.status() != StatusCode::CONFLICT {
        return None;
    }
    serde_json::from_str::<serde_json::Value>(response.body())
        .ok()?
        .get("error")?
        .as_str()
        .filter(|m| m.starts_with("workstream is already active:"))
        .map(str::to_owned)
}

fn is_active_workstream_conflict(error: &anyhow::Error) -> bool {
    active_workstream_conflict_message(error).is_some()
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct HeldLease {
    owner: String,
    expires: jiff::Timestamp,
}

fn parse_held_lease(message: &str) -> Option<HeldLease> {
    let rest = message.strip_prefix("workstream is already active: owned by ")?;
    let (owner, until) = rest.rsplit_once(" until ")?;
    Some(HeldLease { owner: owner.to_owned(), expires: until.trim().parse().ok()? })
}

fn held_lease(error: &anyhow::Error) -> Option<HeldLease> {
    parse_held_lease(&active_workstream_conflict_message(error)?)
}

fn held_lease_wait(expires: jiff::Timestamp, now: jiff::Timestamp, slack: Duration) -> Option<Duration> {
    let remaining = Duration::try_from(expires.duration_since(now)).unwrap_or(Duration::ZERO);
    (remaining <= HELD_LEASE_MAX_WAIT).then(|| remaining + slack)
}

async fn prepare_with_retry(client: &Client, request: &PrepareManagedRunRequest, window: Duration, announce: bool)
    -> Result<PrepareManagedRunResponse> {
    let deadline = tokio::time::Instant::now() + window;
    let mut reported = !announce;
    loop {
        match client.post_json(&prepare_path(), request).await {
            Err(error) if is_active_workstream_conflict(&error) && tokio::time::Instant::now() < deadline => {
                if !reported {
                    eprintln!("ai-memory: another launcher owns this workstream; waiting briefly in case it is finalizing");
                    reported = true;
                }
                tokio::time::sleep(PREPARE_BUSY_RETRY_INTERVAL).await;
            }
            result => return result,
        }
    }
}

/// After the quick window, an interactive launch waits out a lease a dead
/// launcher left (the 409 names its expiry); a lease renewed meanwhile
/// belongs to a live launcher and is reported, never taken over.
async fn wait_out_held_lease(client: &Client, request: &PrepareManagedRunRequest, error: anyhow::Error,
    interrupted: &CancellationToken) -> Result<PrepareManagedRunResponse> {
    let Some(held) = held_lease(&error) else { return Err(error) };
    let Some(wait) = held_lease_wait(held.expires, jiff::Timestamp::now(), HELD_LEASE_EXPIRY_SLACK) else {
        return Err(error);
    };
    eprintln!(
        "ai-memory: the workstream is held by {} until {} — usually a launcher that exited without releasing it. \
         Waiting {}s for that lease to lapse (Ctrl-C to abort; `--new <name>` starts a separate workstream).",
        held.owner, held.expires, wait.as_secs_f64().ceil()
    );
    tokio::select! {
        biased;
        () = interrupted.cancelled() => {
            return Err(error.context("interrupted while waiting for the workstream lease to lapse"));
        }
        () = tokio::time::sleep(wait) => {}
    }
    match prepare_with_retry(client, request, PREPARE_BUSY_RETRY_WINDOW, false).await {
        Err(error) if held_lease(&error).is_some() => Err(error.context(
            "the workstream is still held: its owner renewed the lease, so another launcher is running there; \
             stop it, or pass `--new <name>` for a separate workstream",
        )),
        result => result,
    }
}

/// Upstream's `prepare_managed_run`: scripts keep the short window, an
/// interactive launch also waits out an abandoned lease.
pub(crate) async fn prepare(client: &Client, request: &PrepareManagedRunRequest, interactive: bool,
    interrupted: &CancellationToken) -> Result<PrepareManagedRunResponse> {
    if request.force_unlock {
        return match client.post_json(&prepare_path(), request).await {
            Err(error) if is_active_workstream_conflict(&error) => Err(error.context(
                "--force-unlock was refused: the active lease belongs to another operator, or \
                 the server does not support forced lease recovery",
            )),
            other => other,
        };
    }
    match prepare_with_retry(client, request, PREPARE_BUSY_RETRY_WINDOW, true).await {
        Err(error) if interactive => wait_out_held_lease(client, request, error, interrupted).await,
        result => result,
    }
}

pub(crate) async fn post_empty_with_retry(client: &Client, path: &str, label: &str) -> Result<()> {
    let mut last = None;
    for attempt in 0..3 {
        match client.post_empty(path).await {
            Ok(()) => return Ok(()),
            Err(error) => last = Some(error),
        }
        tokio::time::sleep(Duration::from_millis(250 * (attempt + 1))).await;
    }
    Err(last.unwrap_or_else(|| anyhow!("request failed"))).context(label.to_owned())
}

pub(crate) async fn cancel_after_failure(client: &Client, run_path: &str) {
    let label = "releasing the managed workstream after a launcher failure";
    if let Err(error) = post_empty_with_retry(client, &format!("{run_path}/cancel"), label).await {
        eprintln!("ai-memory: {error:#}; the orphaned lease will expire automatically within 90 seconds");
    }
}

pub(crate) async fn finish_with_retry(client: &Client, run_path: &str, request: &FinishManagedRunRequest)
    -> Result<FinishManagedRunResponse> {
    let path = format!("{run_path}/finish");
    let mut last = None;
    for attempt in 0..3 {
        match client.post_json(&path, request).await {
            Ok(response) => return Ok(response),
            Err(error) => last = Some(error),
        }
        tokio::time::sleep(Duration::from_millis(250 * (attempt + 1))).await;
    }
    Err(last.unwrap_or_else(|| anyhow!("managed finish failed")))
        .context("persisting the managed transcript; the native process has already exited")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum HeartbeatFailureKind {
    Unreachable,
    Rejected,
}

/// Heartbeat failures and recoveries; while the agent owns the terminal a
/// line on stderr would land inside its TUI, so notices wait for its exit.
#[derive(Debug, Default)]
pub(crate) struct HeartbeatHealth {
    consecutive_failures: u64,
    last_failure_kind: Option<HeartbeatFailureKind>,
    first_deferred: Option<String>,
    last_deferred: Option<String>,
    deferred_count: u64,
}

impl HeartbeatHealth {
    pub(crate) fn notify(&mut self, notice: String) {
        self.deferred_count = self.deferred_count.saturating_add(1);
        if self.first_deferred.is_none() {
            self.first_deferred = Some(notice);
        } else {
            self.last_deferred = Some(notice);
        }
    }

    /// The held notices: the first and the latest only.
    pub(crate) fn into_deferred(self) -> Vec<String> {
        let mut lines: Vec<String> = self.first_deferred.into_iter().collect();
        let skipped = self.deferred_count.saturating_sub(2);
        if skipped > 0 {
            lines.push(format!("ai-memory: ({skipped} more managed workstream notices while the harness ran)"));
        }
        lines.extend(self.last_deferred);
        lines
    }

    fn record_failure(&mut self, kind: HeartbeatFailureKind) -> bool {
        let changed = self.last_failure_kind != Some(kind);
        self.consecutive_failures = self.consecutive_failures.saturating_add(1);
        self.last_failure_kind = Some(kind);
        changed
    }

    fn record_success(&mut self) -> bool {
        let recovered = self.consecutive_failures > 0;
        self.consecutive_failures = 0;
        self.last_failure_kind = None;
        recovered
    }
}

fn heartbeat_failure_kind(error: &anyhow::Error) -> HeartbeatFailureKind {
    if error.chain().any(|c| c.downcast_ref::<ServerResponseError>().is_some()) {
        HeartbeatFailureKind::Rejected
    } else {
        HeartbeatFailureKind::Unreachable
    }
}

/// One heartbeat whose failure is the caller's (after a session choice).
pub(crate) async fn post_heartbeat(client: &Client, run_path: &str) -> Result<()> {
    let path = format!("{run_path}/heartbeat");
    tokio::time::timeout(HEARTBEAT_REQUEST_TIMEOUT, client.post_empty(&path))
        .await
        .map_err(|_| anyhow!("request timed out after {HEARTBEAT_REQUEST_TIMEOUT:?}"))
        .and_then(|r| r)
}

pub(crate) async fn send_heartbeat(client: &Client, run_path: &str, health: &mut HeartbeatHealth) {
    let path = format!("{run_path}/heartbeat");
    let result = tokio::time::timeout(HEARTBEAT_REQUEST_TIMEOUT, client.post_empty(&path))
        .await
        .map_err(|_| anyhow!("request timed out after {HEARTBEAT_REQUEST_TIMEOUT:?}"))
        .and_then(|r| r);
    match &result {
        Ok(()) if health.record_success() => {
            health.notify("ai-memory: server connection restored; managed workstream heartbeat resumed".into());
        }
        Ok(()) => {}
        Err(error) if health.record_failure(heartbeat_failure_kind(error)) => {
            let notice = if heartbeat_failure_kind(error) == HeartbeatFailureKind::Rejected {
                format!("ai-memory: managed workstream heartbeat rejected: {error:#}; retrying quietly")
            } else {
                "ai-memory: server unavailable; managed workstream heartbeat will retry quietly".to_owned()
            };
            health.notify(notice);
        }
        Err(_) => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_held_lease_names_its_owner_and_a_bounded_wait() {
        let held = parse_held_lease("workstream is already active: owned by mac:42 until 2026-11-16T10:00:00Z").unwrap();
        assert_eq!(held.owner, "mac:42");
        let now: jiff::Timestamp = "2026-11-16T09:59:30Z".parse().unwrap();
        assert_eq!(held_lease_wait(held.expires, now, Duration::from_secs(1)), Some(Duration::from_secs(31)));
        let far: jiff::Timestamp = "2026-11-16T09:50:00Z".parse().unwrap();
        assert_eq!(held_lease_wait(held.expires, far, Duration::from_secs(1)), None);
        assert!(parse_held_lease("something else").is_none());
    }

    #[test]
    fn deferred_heartbeat_notices_keep_the_first_and_the_latest() {
        let mut health = HeartbeatHealth::default();
        for n in 0..5 {
            health.notify(format!("n{n}"));
        }
        assert_eq!(health.into_deferred(), ["n0", "ai-memory: (3 more managed workstream notices while the harness ran)", "n4"]);
    }
}
