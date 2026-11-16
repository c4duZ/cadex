//! Command-line options, parsed by hand to keep `clap` out of the binary,
//! and the argument list the engine passes itself when it restarts.

use std::path::PathBuf;
use std::time::Duration;

use anyhow::{Context, Result, bail};

/// What `cadex-memory` was started with.
#[derive(Debug)]
pub(crate) struct Args {
    pub(crate) socket: PathBuf,
    pub(crate) data_dir: PathBuf,
    /// Folder of the session tokens the kit writes (`<kitSession>.token`).
    pub(crate) tokens_dir: PathBuf,
    /// Queued hook requests the `cadex memory-hook` client left while the
    /// engine was down; replayed at start.
    pub(crate) spool_dir: PathBuf,
    pub(crate) embeddings: bool,
    /// The wiki's file watcher. Off by default: plan 22 wants no clock- or
    /// disk-driven work while parked; outside edits enter on the next start.
    pub(crate) watcher: bool,
    pub(crate) embed_idle: Duration,
    /// Never exit for lack of sessions (the app's warm-up, tests).
    pub(crate) keep_alive: bool,
    /// The `claude` pids still alive when the previous image restarted.
    pub(crate) sessions: Vec<i32>,
    /// The data folder's lock and the listening socket, kept open across a
    /// restart so no second engine starts and no hook finds the socket gone.
    pub(crate) lock_fd: Option<i32>,
    pub(crate) listen_fd: Option<i32>,
}

/// The tokens folder of the macOS app (SessionKit.tokensFolder).
fn default_tokens_dir() -> PathBuf {
    let home = std::env::var_os("HOME").unwrap_or_default();
    PathBuf::from(home).join("Library/Application Support/Cadex/sessions")
}

fn value(it: &mut impl Iterator<Item = String>, name: &str) -> Result<String> {
    it.next().with_context(|| format!("{name} needs a value"))
}

fn fd(it: &mut impl Iterator<Item = String>, name: &str) -> Result<Option<i32>> {
    Ok(Some(value(it, name)?.parse().with_context(|| format!("{name}: not a descriptor"))?))
}

/// Parse the arguments after the program name.
pub(crate) fn parse(argv: &[String]) -> Result<Args> {
    let (mut socket, mut data_dir, mut tokens_dir, mut spool_dir) = (None, None, None, None);
    let mut args = Args {
        socket: PathBuf::new(),
        data_dir: PathBuf::new(),
        tokens_dir: PathBuf::new(),
        spool_dir: PathBuf::new(),
        embeddings: true,
        watcher: false,
        embed_idle: Duration::from_secs(60),
        keep_alive: false,
        sessions: Vec::new(),
        lock_fd: None,
        listen_fd: None,
    };
    let mut it = argv.iter().cloned();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--socket" => socket = Some(PathBuf::from(value(&mut it, &arg)?)),
            "--data-dir" => data_dir = Some(PathBuf::from(value(&mut it, &arg)?)),
            "--tokens-dir" => tokens_dir = Some(PathBuf::from(value(&mut it, &arg)?)),
            "--spool-dir" => spool_dir = Some(PathBuf::from(value(&mut it, &arg)?)),
            "--no-embeddings" => args.embeddings = false,
            "--watcher" => args.watcher = true,
            "--keep-alive" => args.keep_alive = true,
            "--embed-idle-secs" => {
                args.embed_idle = Duration::from_secs(value(&mut it, &arg)?.parse()?);
            }
            "--sessions" => {
                let list = value(&mut it, &arg)?;
                args.sessions = list.split(',').filter_map(|p| p.trim().parse().ok()).collect();
            }
            "--lock-fd" => args.lock_fd = fd(&mut it, &arg)?,
            "--listen-fd" => args.listen_fd = fd(&mut it, &arg)?,
            other => bail!("unknown argument {other}"),
        }
    }
    args.socket = socket.context("--socket <path> is required")?;
    args.data_dir = data_dir.context("--data-dir <path> is required")?;
    args.tokens_dir = tokens_dir.unwrap_or_else(default_tokens_dir);
    args.spool_dir = spool_dir.unwrap_or_else(|| args.data_dir.join("spool"));
    Ok(args)
}

/// The arguments of the restarted image: the same ones, without what the
/// previous restart added, plus the live sessions and the kept descriptors.
pub(crate) fn restart_argv(argv: &[String], sessions: &[i32], lock_fd: i32, listen_fd: i32) -> Vec<String> {
    let mut out = Vec::with_capacity(argv.len() + 6);
    let mut it = argv.iter();
    while let Some(arg) = it.next() {
        if matches!(arg.as_str(), "--sessions" | "--lock-fd" | "--listen-fd") {
            it.next();
            continue;
        }
        out.push(arg.clone());
    }
    if !sessions.is_empty() {
        let list: Vec<String> = sessions.iter().map(i32::to_string).collect();
        out.extend(["--sessions".into(), list.join(",")]);
    }
    out.extend(["--lock-fd".into(), lock_fd.to_string()]);
    out.extend(["--listen-fd".into(), listen_fd.to_string()]);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strings(words: &[&str]) -> Vec<String> {
        words.iter().map(|w| (*w).to_string()).collect()
    }

    #[test]
    fn defaults_put_the_spool_in_the_data_folder_and_the_watcher_off() {
        let args = parse(&strings(&["--socket", "/s", "--data-dir", "/d"])).unwrap();
        assert_eq!(args.spool_dir, PathBuf::from("/d/spool"));
        assert!(args.tokens_dir.ends_with("Cadex/sessions"));
        assert!(!args.watcher && !args.keep_alive && args.embeddings);
        assert!(args.sessions.is_empty() && args.lock_fd.is_none());
    }

    #[test]
    fn sessions_and_descriptors_are_read() {
        let args = parse(&strings(&[
            "--socket", "/s", "--data-dir", "/d", "--sessions", "12,x,34", "--lock-fd", "5",
            "--listen-fd", "6", "--keep-alive", "--watcher",
        ]))
        .unwrap();
        assert_eq!(args.sessions, vec![12, 34]);
        assert_eq!((args.lock_fd, args.listen_fd), (Some(5), Some(6)));
        assert!(args.keep_alive && args.watcher);
        assert!(parse(&strings(&["--socket", "/s"])).is_err());
        assert!(parse(&strings(&["--socket", "/s", "--data-dir", "/d", "--bogus"])).is_err());
    }

    #[test]
    fn a_restart_replaces_what_the_previous_one_added() {
        let first = strings(&["--socket", "/s", "--data-dir", "/d", "--no-embeddings"]);
        let once = restart_argv(&first, &[10, 11], 3, 4);
        assert_eq!(
            once,
            strings(&["--socket", "/s", "--data-dir", "/d", "--no-embeddings", "--sessions", "10,11",
                "--lock-fd", "3", "--listen-fd", "4"])
        );
        let twice = restart_argv(&once, &[], 7, 8);
        assert_eq!(
            twice,
            strings(&["--socket", "/s", "--data-dir", "/d", "--no-embeddings", "--lock-fd", "7",
                "--listen-fd", "8"])
        );
        assert!(parse(&twice).is_ok());
    }
}
