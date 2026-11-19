//! Plan 40 A2: proof that reading the panel leaves the memory as it was,
//! byte for byte.
//!
//! The method: the store is opened and CLOSED with `Store::close` (which
//! drains the writer's queue, then runs `wal_checkpoint(TRUNCATE)`) on both
//! sides of the comparison, and every file under the folder is hashed while
//! nothing holds the database. Hashing with the store open would be unsound:
//! a write sitting in the WAL may not be checkpointed yet, a write the writer
//! has queued but not run is in no file, and `Store::open` itself writes
//! (`PRAGMA optimize`, the idempotent backfills). So the caller first does
//! one open+close cycle with no requests (the baseline, which absorbs what
//! opening writes), then one with every GET; a write any route made, sent
//! before the close, is in the main file or the WAL by the second hash.
//! `-shm` files are skipped: SQLite's WAL index holds read marks that every
//! reader rewrites, and it carries no data. Paths are compared as well as
//! contents, so a created or deleted file fails too; times are not compared.

#![allow(dead_code)]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

/// Relative path to SHA-256 (hex) of every file under `root`, `-shm` aside.
pub type Snapshot = BTreeMap<PathBuf, String>;

pub fn take(root: &Path) -> Snapshot {
    let mut out = Snapshot::new();
    walk(root, root, &mut out);
    out
}

fn walk(root: &Path, dir: &Path, out: &mut Snapshot) {
    let mut entries: Vec<_> = std::fs::read_dir(dir).expect("read seed folder").flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let path = entry.path();
        let kind = entry.file_type().expect("file type");
        if kind.is_dir() {
            walk(root, &path, out);
        } else if kind.is_file() && !path.to_string_lossy().ends_with("-shm") {
            let bytes = std::fs::read(&path).expect("read seed file");
            let hex = Sha256::digest(&bytes).iter().map(|b| format!("{b:02x}")).collect();
            out.insert(path.strip_prefix(root).unwrap().to_path_buf(), hex);
        }
    }
}

/// The paths that differ between two snapshots (added, removed or changed).
pub fn diff(before: &Snapshot, after: &Snapshot) -> Vec<String> {
    let mut out = Vec::new();
    for (path, hash) in before {
        match after.get(path) {
            None => out.push(format!("removed {}", path.display())),
            Some(h) if h != hash => out.push(format!("changed {}", path.display())),
            Some(_) => {}
        }
    }
    for path in after.keys().filter(|p| !before.contains_key(*p)) {
        out.push(format!("added {}", path.display()));
    }
    out
}
