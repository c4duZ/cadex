//! The memory agent's settings, `<data-dir>/agent.json` (ADR 0029, plan 22
//! phase G, 2026-11-16). The app writes the file (memory.backgroundAgent,
//! memory.dailyBudgetUsd, memory.requireApproval and the accounts); the
//! engine reads it again at each job, so a change takes effect at the next
//! job without a restart, and never writes it.
//!
//! A missing or unreadable file is the default: off. A value that makes no
//! sense (a negative or non-finite budget) reads as a zero budget, so a bad
//! file can only stop the agent, never let it spend more.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde::Deserialize;

/// What `agent.json` holds.
#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub(crate) struct Config {
    /// memory.backgroundAgent: the event-triggered jobs run only when on.
    pub(crate) enabled: bool,
    /// memory.dailyBudgetUsd: the most the agent spends in a local day.
    pub(crate) daily_budget_usd: f64,
    /// memory.requireApproval: auto-improve stages its proposals for the
    /// owner instead of applying them.
    pub(crate) require_approval: bool,
    /// `--model` of each call.
    pub(crate) model: String,
    /// `--max-budget-usd` of each call.
    pub(crate) call_budget_usd: f64,
    /// The `claude` to run; `None`: the first of `CANDIDATES` that exists.
    pub(crate) claude: Option<PathBuf>,
    /// The default account's config folder; `None`: Claude Code's own
    /// default (no `CLAUDE_CONFIG_DIR`).
    pub(crate) config_dir: Option<PathBuf>,
    /// A project's account, by the path of its repository root.
    pub(crate) project_accounts: HashMap<String, PathBuf>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            enabled: false,
            daily_budget_usd: 1.0,
            require_approval: true,
            model: "haiku".into(),
            call_budget_usd: 0.25,
            claude: None,
            config_dir: None,
            project_accounts: HashMap::new(),
        }
    }
}

/// Where Claude Code's installers put `claude`, in the order tried: the
/// native installer, Homebrew on Apple silicon, Homebrew on Intel.
const CANDIDATES: [&str; 3] = [".local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"];

pub(crate) fn file(data_dir: &Path) -> PathBuf {
    data_dir.join("agent.json")
}

/// A budget that can be compared: not negative, not NaN.
fn sane(usd: f64) -> f64 {
    if usd.is_finite() && usd > 0.0 { usd } else { 0.0 }
}

/// The settings now; off when the file is missing or does not parse.
pub(crate) fn read(data_dir: &Path) -> Config {
    let path = file(data_dir);
    let Ok(text) = std::fs::read_to_string(&path) else { return Config::default() };
    match serde_json::from_str::<Config>(&text) {
        Ok(mut config) => {
            config.daily_budget_usd = sane(config.daily_budget_usd);
            config.call_budget_usd = sane(config.call_budget_usd);
            if config.model.trim().is_empty() {
                config.model = Config::default().model;
            }
            config
        }
        Err(error) => {
            tracing::warn!(path = %path.display(), %error, "agent.json does not parse; the memory agent stays off");
            Config::default()
        }
    }
}

/// `path` made canonical when it exists (a temporary folder under /var is
/// /private/var once resolved), as written otherwise.
fn canonical(path: &Path) -> PathBuf {
    path.canonicalize().unwrap_or_else(|_| path.to_path_buf())
}

impl Config {
    /// The account folder of the project whose repository root is `root`:
    /// its entry in `project_accounts`, else the default account.
    pub(crate) fn account_for(&self, root: Option<&Path>) -> Option<PathBuf> {
        if let Some(root) = root {
            let root = canonical(root);
            let found = self.project_accounts.iter().find(|(key, _)| canonical(Path::new(key)) == root);
            if let Some((_, dir)) = found {
                return Some(dir.clone());
            }
        }
        self.config_dir.clone()
    }

    /// The `claude` executable: the configured one, else the first installed.
    pub(crate) fn claude_binary(&self, home: Option<&Path>) -> Option<PathBuf> {
        if let Some(path) = &self.claude {
            return Some(path.clone());
        }
        CANDIDATES.iter().find_map(|candidate| {
            let path = match candidate.strip_prefix('/') {
                Some(_) => PathBuf::from(candidate),
                None => home?.join(candidate),
            };
            path.is_file().then_some(path)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_missing_or_bad_file_is_off_and_bad_budgets_are_zero() {
        let tmp = tempfile::tempdir().unwrap();
        assert!(!read(tmp.path()).enabled);
        std::fs::write(file(tmp.path()), "{not json").unwrap();
        assert!(!read(tmp.path()).enabled);
        std::fs::write(file(tmp.path()), r#"{"enabled": true, "daily_budget_usd": -3, "call_budget_usd": 0.1}"#).unwrap();
        let config = read(tmp.path());
        assert!(config.enabled && config.require_approval);
        assert_eq!((config.daily_budget_usd, config.call_budget_usd, config.model.as_str()), (0.0, 0.1, "haiku"));
    }

    #[test]
    fn a_project_account_wins_over_the_default_one() {
        let tmp = tempfile::tempdir().unwrap();
        let repo = tmp.path().join("acme");
        std::fs::create_dir_all(&repo).unwrap();
        let mut config = Config { config_dir: Some("/accounts/main".into()), ..Config::default() };
        config.project_accounts.insert(repo.to_string_lossy().into_owned(), "/accounts/work".into());
        assert_eq!(config.account_for(Some(&repo.canonicalize().unwrap())), Some("/accounts/work".into()));
        assert_eq!(config.account_for(Some(Path::new("/elsewhere"))), Some("/accounts/main".into()));
        assert_eq!(config.account_for(None), Some("/accounts/main".into()));
    }
}
