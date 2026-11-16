//! What the import remembers between engine runs, in `<data-dir>/imports/`:
//! - `backfill-<workspace id>-<project id>`: a project's history import,
//!   `started` while it runs (a run cut short by the engine's exit resumes at
//!   the next SessionStart) and `done` after; upstream keeps a sentinel per
//!   checkout for the same reason (backfill.rs, `sentinel_path`).
//! - `outside.json`: per account folder, the newest transcript time every
//!   earlier start has handled, so a start only reads what changed since.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

fn folder(data_dir: &Path) -> PathBuf {
    data_dir.join("imports")
}

/// Write by rename, so a reader never sees half a file.
fn write_atomic(path: &Path, text: &str) {
    let Some(dir) = path.parent() else { return };
    let tmp = path.with_extension("tmp");
    let done = std::fs::create_dir_all(dir)
        .and_then(|()| std::fs::write(&tmp, text))
        .and_then(|()| std::fs::rename(&tmp, path));
    if let Err(error) = done {
        tracing::warn!(%error, file = %path.display(), "import state not saved");
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Backfill {
    Never,
    Started,
    Done,
}

/// A project's history-import marker.
pub(crate) struct BackfillMarker(PathBuf);

impl BackfillMarker {
    pub(crate) fn new(data_dir: &Path, workspace: &impl std::fmt::Display, project: &impl std::fmt::Display) -> Self {
        Self(folder(data_dir).join(format!("backfill-{workspace}-{project}")))
    }

    pub(crate) fn read(&self) -> Backfill {
        match std::fs::read_to_string(&self.0).as_deref().map(str::trim) {
            Ok("done") => Backfill::Done,
            Ok(_) => Backfill::Started,
            Err(_) => Backfill::Never,
        }
    }

    pub(crate) fn set(&self, state: Backfill) {
        let text = if state == Backfill::Done { "done\n" } else { "started\n" };
        write_atomic(&self.0, text);
    }
}

/// The per-account checkpoints of the import at engine start.
pub(crate) struct Checkpoints {
    path: PathBuf,
    by_account: BTreeMap<String, u64>,
}

impl Checkpoints {
    pub(crate) fn load(data_dir: &Path) -> Self {
        let path = folder(data_dir).join("outside.json");
        let by_account = std::fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default();
        Self { path, by_account }
    }

    /// Transcripts modified up to this time were handled.
    pub(crate) fn get(&self, account: &Path) -> Option<SystemTime> {
        let ms = *self.by_account.get(account.to_string_lossy().as_ref())?;
        Some(UNIX_EPOCH + Duration::from_millis(ms))
    }

    pub(crate) fn set(&mut self, account: &Path, until: SystemTime) {
        let ms = until.duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64);
        self.by_account.insert(account.to_string_lossy().into_owned(), ms);
    }

    pub(crate) fn save(&self) {
        if let Ok(text) = serde_json::to_string_pretty(&self.by_account) {
            write_atomic(&self.path, &text);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn markers_and_checkpoints_survive_a_restart() {
        let tmp = tempfile::tempdir().unwrap();
        let marker = BackfillMarker::new(tmp.path(), &"w", &"p");
        assert_eq!(marker.read(), Backfill::Never);
        marker.set(Backfill::Started);
        assert_eq!(BackfillMarker::new(tmp.path(), &"w", &"p").read(), Backfill::Started);
        marker.set(Backfill::Done);
        assert_eq!(marker.read(), Backfill::Done);

        let at = UNIX_EPOCH + Duration::from_millis(1_700_000_000_123);
        let mut points = Checkpoints::load(tmp.path());
        assert!(points.get(Path::new("/a")).is_none());
        points.set(Path::new("/a"), at);
        points.save();
        assert_eq!(Checkpoints::load(tmp.path()).get(Path::new("/a")), Some(at));
    }
}
