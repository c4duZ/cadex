//! The automatic memory folders watched while the engine runs (plan 22,
//! phase C): `<data-dir>/auto/`, by FSEvents (the `notify` crate, already in
//! upstream's tree for its wiki watcher), so nothing runs while nothing
//! changes. Changes are gathered for 500 ms (a session saving writes the
//! topic file and then MEMORY.md), then each folder touched gets its index
//! rebuilt (auto_index.rs) and its pages brought in line (auto_wiki.rs).
//! At start every folder is reconciled once: what changed while the engine
//! was down. The change our own MEMORY.md write causes is recognised by its
//! text and skipped.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use notify::{RecursiveMode, Watcher};
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use crate::auto_index::{INDEX, is_topic_name, rebuild_folder};
use crate::auto_wiki::{PROJECT_FILE, sync};
use crate::restart::InFlight;

/// How long changes are gathered before a folder is processed.
const SETTLE: Duration = Duration::from_millis(500);

/// What the watcher needs from the engine.
pub(crate) struct Context {
    pub(crate) router: Router,
    pub(crate) data_dir: PathBuf,
    pub(crate) in_flight: Arc<InFlight>,
    pub(crate) stop: CancellationToken,
}

/// The automatic memory folders: `auto/<project>` and
/// `auto/<account>/<project>`, each with the app's project.json.
fn folders(root: &Path) -> Vec<PathBuf> {
    let children = |dir: &Path| -> Vec<PathBuf> {
        std::fs::read_dir(dir).map(|e| e.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect()).unwrap_or_default()
    };
    let mut found = Vec::new();
    for first in children(root) {
        if first.join(PROJECT_FILE).is_file() {
            found.push(first.clone());
        }
        found.extend(children(&first).into_iter().filter(|d| d.join(PROJECT_FILE).is_file()));
    }
    found.sort();
    found
}

/// The folder a changed path belongs to, by the names it can have there.
fn folder_of(root: &Path, path: &Path) -> Option<PathBuf> {
    let rel = path.strip_prefix(root).ok()?;
    let depth = rel.components().count();
    let name = path.file_name()?.to_str()?;
    let dir = if (1..=2).contains(&depth) && path.is_dir() { path.to_path_buf() } else { path.parent()?.to_path_buf() };
    let ours = name == INDEX || name == PROJECT_FILE || is_topic_name(name) || name.starts_with(".MEMORY.md") || dir == path;
    (ours && dir.join(PROJECT_FILE).is_file()).then_some(dir)
}

/// Whether a path is the index or our temporary file for it.
fn is_index_write(path: &Path) -> bool {
    path.file_name().and_then(|n| n.to_str()).is_some_and(|n| n == INDEX || n.starts_with(".MEMORY.md"))
}

struct Watch {
    ctx: Context,
    /// The index text we last wrote, per folder.
    written: HashMap<PathBuf, String>,
}

impl Watch {
    async fn process(&mut self, dir: &Path) {
        match rebuild_folder(dir) {
            Ok(Some(text)) => {
                self.written.insert(dir.to_path_buf(), text);
            }
            Ok(None) => {}
            Err(error) => tracing::warn!(dir = %dir.display(), error = %format!("{error:#}"), "MEMORY.md not rebuilt"),
        }
        let _hold = self.ctx.in_flight.hold();
        match sync(&self.ctx.router, &self.ctx.data_dir, dir).await {
            // Each write and delete is a commit of the wiki's git already
            // (upstream's MCP path).
            Ok(done) if done.written + done.deleted > 0 => {
                tracing::info!(dir = %dir.display(), written = done.written, deleted = done.deleted, "automatic memory pages synced");
            }
            Ok(_) => {}
            Err(error) => tracing::info!(dir = %dir.display(), error = %format!("{error:#}"), "automatic memory folder skipped"),
        }
    }

    /// A batch of changes for one folder that is only our own index write.
    fn only_ours(&self, dir: &Path, paths: &BTreeSet<PathBuf>) -> bool {
        paths.iter().all(|p| is_index_write(p))
            && self.written.get(dir).is_some_and(|text| std::fs::read_to_string(dir.join(INDEX)).ok().as_ref() == Some(text))
    }
}

/// Watch until the engine stops. Without a watcher (FSEvents refused) the
/// start's reconcile still runs.
pub(crate) async fn run(ctx: Context) {
    let root = ctx.data_dir.join("auto");
    if let Err(error) = std::fs::create_dir_all(&root) {
        return tracing::warn!(%error, "no automatic memory folder");
    }
    // FSEvents reports real paths (/private/var for /var).
    let root = root.canonicalize().unwrap_or(root);
    let (tx, mut rx) = mpsc::unbounded_channel::<PathBuf>();
    let watcher = notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
        if let Ok(event) = event {
            event.paths.into_iter().for_each(|p| drop(tx.send(p)));
        }
    })
    .and_then(|mut w| w.watch(&root, RecursiveMode::Recursive).map(|()| w));
    if let Err(error) = &watcher {
        tracing::warn!(%error, "automatic memory folders not watched; reconciled at start only");
    }
    let mut watch = Watch { ctx, written: HashMap::new() };
    for dir in folders(&root) {
        if watch.ctx.stop.is_cancelled() {
            return;
        }
        watch.process(&dir).await;
    }
    let _watcher = watcher;
    loop {
        let first = tokio::select! {
            p = rx.recv() => match p { Some(p) => p, None => return },
            () = watch.ctx.stop.cancelled() => return,
        };
        tokio::select! {
            () = tokio::time::sleep(SETTLE) => {}
            () = watch.ctx.stop.cancelled() => return,
        }
        let mut changed: BTreeMap<PathBuf, BTreeSet<PathBuf>> = BTreeMap::new();
        let mut add = |p: PathBuf| {
            if let Some(dir) = folder_of(&root, &p) {
                changed.entry(dir).or_default().insert(p);
            }
        };
        add(first);
        while let Ok(p) = rx.try_recv() {
            add(p);
        }
        for (dir, paths) in changed {
            if !watch.only_ours(&dir, &paths) {
                watch.process(&dir).await;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn changed_paths_map_to_their_folder() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        let shared = root.join("k1");
        let own = root.join("acct/k2");
        for dir in [&shared, &own] {
            std::fs::create_dir_all(dir).unwrap();
            std::fs::write(dir.join(PROJECT_FILE), "{}").unwrap();
        }
        assert_eq!(folders(root), vec![own.clone(), shared.clone()]);
        assert_eq!(folder_of(root, &shared.join("topic.md")), Some(shared.clone()));
        assert_eq!(folder_of(root, &own.join(INDEX)), Some(own.clone()));
        assert_eq!(folder_of(root, &own), Some(own.clone()));
        assert_eq!(folder_of(root, &own.join("notes.txt")), None);
        assert_eq!(folder_of(root, &root.join("acct/k3/topic.md")), None, "no project.json: not ours");
        assert!(is_index_write(&own.join(".MEMORY.md.cadex-1.tmp")) && !is_index_write(&own.join("t.md")));
    }
}
