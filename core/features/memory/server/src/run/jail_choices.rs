//! The jail checklist answers remembered per checkout, so the next run
//! offers them again and Enter keeps them. Never in the repository: a
//! repository must not be able to grant itself a credential or a mount.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged), crates/ai-memory-cli/src/commands/
//! jail_choices.rs: `Store`, `Remembered`, `Applied`, `load`, `save`, `apply`
//! and `remember`. Changed for Cadex (2026-11-16): the file is
//! `<data-dir>/run/jail-choices.json`, never upstream's data dir.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use ai_memory_workstream::JailChecklistItem;
use anyhow::{Context as _, Result};
use serde::{Deserialize, Serialize};

use super::jail_folders::ExtraFolder;

const FILE: &str = "jail-choices.json";
const MAX_CHECKOUTS: usize = 200;

#[derive(Debug, Default, Serialize, Deserialize)]
struct Store {
    #[serde(default)]
    checkouts: BTreeMap<String, Remembered>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct Remembered {
    #[serde(default)]
    pub(crate) enabled: Vec<String>,
    #[serde(default)]
    pub(crate) disabled: Vec<String>,
    #[serde(default)]
    pub(crate) folders: Vec<ExtraFolder>,
    #[serde(default)]
    pub(crate) saved_at: String,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct Applied {
    pub(crate) new: Vec<&'static str>,
    pub(crate) gone: Vec<String>,
}

fn path(run_dir: &Path) -> PathBuf {
    run_dir.join(FILE)
}

fn read_store(run_dir: &Path) -> Store {
    std::fs::read_to_string(path(run_dir)).ok().and_then(|raw| serde_json::from_str(&raw).ok()).unwrap_or_default()
}

pub(crate) fn load(run_dir: &Path, checkout: &str) -> Option<Remembered> {
    read_store(run_dir).checkouts.remove(checkout)
}

pub(crate) fn save(run_dir: &Path, checkout: &str, remembered: Remembered) -> Result<()> {
    let mut store = read_store(run_dir);
    store.checkouts.insert(checkout.to_owned(), remembered);
    while store.checkouts.len() > MAX_CHECKOUTS {
        let Some(oldest) = store.checkouts.iter().min_by(|a, b| a.1.saved_at.cmp(&b.1.saved_at)).map(|(k, _)| k.clone()) else {
            break;
        };
        store.checkouts.remove(&oldest);
    }
    let body = serde_json::to_string_pretty(&store).context("encoding the jail choices")?;
    std::fs::create_dir_all(run_dir).with_context(|| format!("creating {}", run_dir.display()))?;
    ai_memory_wiki::write_atomic(&path(run_dir), body.as_bytes())
        .map(|_| ())
        .with_context(|| format!("writing {}", path(run_dir).display()))
}

pub(crate) fn apply(items: &mut [JailChecklistItem], remembered: &Remembered) -> Applied {
    let mut applied = Applied::default();
    for item in items.iter_mut() {
        let stem = item.toggle.stem;
        if remembered.enabled.iter().any(|saved| saved == stem) {
            item.checked = true;
        } else if remembered.disabled.iter().any(|saved| saved == stem) {
            item.checked = false;
        } else {
            applied.new.push(stem);
        }
    }
    applied.gone = remembered
        .enabled
        .iter()
        .filter(|saved| !items.iter().any(|item| item.toggle.stem == saved.as_str()))
        .cloned()
        .collect();
    applied
}

pub(crate) fn remember(items: &[JailChecklistItem], folders: Vec<ExtraFolder>, saved_at: String) -> Remembered {
    let (on, off): (Vec<_>, Vec<_>) = items.iter().partition(|item| item.checked);
    let stems = |rows: Vec<&JailChecklistItem>| rows.into_iter().map(|item| item.toggle.stem.to_owned()).collect();
    Remembered { enabled: stems(on), disabled: stems(off), folders, saved_at }
}
