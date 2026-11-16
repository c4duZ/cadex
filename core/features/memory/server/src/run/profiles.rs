//! The `[run]` settings of upstream's own client config, read only: the
//! `--profile` presets, `exit_prompt`, `require_server` and the retired
//! `claude_true_yolo`. Cadex never writes that file.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25): `RunSettings`, `RunProfile`,
//! `validate_run_profiles`, `default_data_dir` and the `[run]` env overrides
//! of `Config::load_with_runtime_env` (crates/ai-memory-cli/src/config.rs);
//! `unknown_run_profile`, `resolve_run_env`, `upsert_env` (commands/run.rs).
//! Changed for Cadex (2026-11-16): only `[run]` and `claude_true_yolo` are
//! read; a file that does not parse fails only a `--profile` launch (any
//! other launch warns and goes on with the defaults: Cadex does not depend
//! on that file); the profile-name hint quotes the key by hand (upstream
//! uses `toml_edit::Key`).

use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow, bail};
use serde::Deserialize;

/// `[run]`: the launcher's settings.
#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct RunSettings {
    pub(crate) exit_prompt: bool,
    pub(crate) profiles: BTreeMap<String, RunProfile>,
    pub(crate) require_server: bool,
}

impl Default for RunSettings {
    fn default() -> Self {
        Self { exit_prompt: true, profiles: BTreeMap::new(), require_server: false }
    }
}

/// One named env-only launch preset.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct RunProfile {
    pub(crate) env: BTreeMap<String, String>,
}

/// What `cadex-memory run` reads from upstream's config.
#[derive(Debug, Clone, Default)]
pub(crate) struct Settings {
    pub(crate) run: RunSettings,
    pub(crate) claude_true_yolo: bool,
    /// Why the file could not be used, when it could not.
    pub(crate) load_error: Option<String>,
}

/// Upstream's `default_data_dir`: `dirs::data_local_dir()/ai-memory`.
fn config_path() -> PathBuf {
    let data_dir = std::env::var_os("AI_MEMORY_DATA_DIR")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| dirs::data_local_dir().unwrap_or_else(|| PathBuf::from(".")).join("ai-memory"));
    data_dir.join("config.toml")
}

fn is_truthy(raw: &str) -> bool {
    matches!(raw.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on")
}

fn read_file(path: &Path) -> Result<(RunSettings, bool)> {
    let text = match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok((RunSettings::default(), false)),
        Err(error) => return Err(error).with_context(|| format!("reading {}", path.display())),
    };
    let table: toml::Table = toml::from_str(&text).with_context(|| format!("parsing {}", path.display()))?;
    let run = match table.get("run") {
        Some(value) => value.clone().try_into::<RunSettings>().with_context(|| format!("[run] in {}", path.display()))?,
        None => RunSettings::default(),
    };
    validate_run_profiles(&run)?;
    let true_yolo = table.get("claude_true_yolo").and_then(toml::Value::as_bool).unwrap_or(false);
    Ok((run, true_yolo))
}

/// Read the file (if any) and the `AI_MEMORY_RUN_*` overrides.
pub(crate) fn load() -> Settings {
    let path = config_path();
    let mut settings = match read_file(&path) {
        Ok((run, claude_true_yolo)) => Settings { run, claude_true_yolo, load_error: None },
        Err(error) => Settings { load_error: Some(format!("{error:#}")), ..Settings::default() },
    };
    if std::env::var("AI_MEMORY_RUN_REQUIRE_SERVER").is_ok_and(|raw| is_truthy(&raw)) {
        settings.run.require_server = true;
    }
    if let Ok(raw) = std::env::var("AI_MEMORY_RUN_EXIT_PROMPT") {
        match raw.trim().parse() {
            Ok(value) => settings.run.exit_prompt = value,
            Err(_) => settings.load_error = Some("AI_MEMORY_RUN_EXIT_PROMPT must be true or false".into()),
        }
    }
    settings
}

fn validate_run_profiles(run: &RunSettings) -> Result<()> {
    const MAX_PROFILES: usize = 128;
    const MAX_PROFILE_NAME: usize = 64;
    const MAX_ENV_PER_PROFILE: usize = 128;
    const MAX_ENV_KEY: usize = 256;
    const MAX_ENV_VALUE: usize = 64 * 1024;
    if run.profiles.len() > MAX_PROFILES {
        bail!("run.profiles may contain at most {MAX_PROFILES} profiles");
    }
    for (name, profile) in &run.profiles {
        if name.is_empty()
            || name.len() > MAX_PROFILE_NAME
            || !name.bytes().all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
        {
            bail!("invalid run profile name {name:?}; use 1-{MAX_PROFILE_NAME} ASCII letters, digits, '.', '_' or '-'");
        }
        if profile.env.len() > MAX_ENV_PER_PROFILE {
            bail!("run profile {name:?} may contain at most {MAX_ENV_PER_PROFILE} environment entries");
        }
        let mut folded = HashSet::with_capacity(profile.env.len());
        for (key, value) in &profile.env {
            if key.is_empty() || key.len() > MAX_ENV_KEY || key.contains(['=', '\0']) {
                bail!("run profile {name:?} has invalid environment key {key:?}");
            }
            if value.len() > MAX_ENV_VALUE || value.contains('\0') {
                bail!("run profile {name:?} environment value for {key:?} is invalid or exceeds {MAX_ENV_VALUE} bytes");
            }
            if !folded.insert(key.to_ascii_uppercase()) {
                bail!("run profile {name:?} repeats environment key {key:?} with different ASCII case");
            }
        }
    }
    Ok(())
}

/// The profile `--profile` names, or upstream's error for an unknown one.
pub(crate) fn profile<'a>(settings: &'a Settings, name: &str) -> Result<&'a RunProfile> {
    if let Some(error) = &settings.load_error {
        bail!("loading configuration for --profile: {error}");
    }
    settings.run.profiles.get(name).ok_or_else(|| unknown_run_profile(&settings.run, name))
}

fn unknown_run_profile(run: &RunSettings, name: &str) -> anyhow::Error {
    if !run.profiles.is_empty() {
        let known = run.profiles.keys().map(String::as_str).collect::<Vec<_>>();
        return anyhow!("unknown run profile {name:?}; defined profiles: {}", known.join(", "));
    }
    let bare = !name.is_empty() && name.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-'));
    let key = if bare { name.to_owned() } else { format!("{name:?}") };
    anyhow!(
        "unknown run profile {name:?}; none are defined. Add to your config.toml:\n\n  \
         [run.profiles.{key}.env]\n  CLAUDE_CONFIG_DIR = \"/absolute/path\""
    )
}

/// Profile, then `--env-file` lines, then `--env` entries: a later source
/// wins on the same key, and file order is kept.
pub(crate) fn resolve_run_env(profile: Option<&RunProfile>, env_file: Option<&Path>, env_args: &[(String, String)])
    -> Result<Vec<(String, String)>> {
    let mut merged: Vec<(String, String)> = Vec::new();
    if let Some(profile) = profile {
        for (key, value) in &profile.env {
            upsert_env(&mut merged, key.clone(), value.clone());
        }
    }
    if let Some(path) = env_file {
        let contents = std::fs::read_to_string(path).with_context(|| format!("reading --env-file {}", path.display()))?;
        let contents = contents.strip_prefix('\u{feff}').unwrap_or(&contents);
        for (line_number, line) in contents.lines().enumerate() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            let (key, value) = super::args::parse_env_kv(trimmed)
                .map_err(|error| anyhow!("{}:{}: {error}", path.display(), line_number + 1))?;
            upsert_env(&mut merged, key, value);
        }
    }
    for (key, value) in env_args {
        upsert_env(&mut merged, key.clone(), value.clone());
    }
    Ok(merged)
}

pub(crate) fn upsert_env(entries: &mut Vec<(String, String)>, key: String, value: String) {
    if let Some(existing) = entries.iter_mut().find(|(existing, _)| *existing == key) {
        existing.1 = value;
    } else {
        entries.push((key, value));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn profile_then_file_then_flags_win_and_bad_names_are_refused() {
        let dir = tempfile::tempdir().unwrap();
        let config = dir.path().join("config.toml");
        std::fs::write(&config, "[run.profiles.work.env]\nA = 'profile'\nB = 'profile'\nC = 'profile'\n").unwrap();
        let (run, _) = read_file(&config).unwrap();
        let file = dir.path().join("env");
        std::fs::write(&file, "\u{feff}# c\nB=file\nC=file\n").unwrap();
        let env = resolve_run_env(run.profiles.get("work"), Some(&file), &[("C".into(), "flag".into())]).unwrap();
        assert_eq!(env, [("A".into(), "profile".into()), ("B".into(), "file".into()), ("C".into(), "flag".into())]);
        let settings = Settings { run, ..Settings::default() };
        assert!(profile(&settings, "home").unwrap_err().to_string().contains("defined profiles: work"));
        std::fs::write(&config, "[run.profiles.'bad name'.env]\nA = 'x'\n").unwrap();
        assert!(read_file(&config).is_err());
        std::fs::write(&config, "[run]\nnope = 1\n").unwrap();
        assert!(read_file(&config).is_err());
        let none = Settings::default();
        assert!(profile(&none, "a.b").unwrap_err().to_string().contains("[run.profiles.\"a.b\".env]"));
    }
}
