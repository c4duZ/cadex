//! The workstream context packet for harnesses without a SessionStart hook
//! that could fetch it: Crush reads it as a global context file of a
//! generated config dir (`CRUSH_GLOBAL_CONFIG`), Grok as `--rules` text.
//! Both are acknowledged (`/context/accept`) only after the child spawns.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged), crates/ai-memory-cli/src/commands/
//! run.rs: `fetch_grok_context`, `prepare_crush_context`,
//! `crush_context_source`, `write_crush_context_config`, `write_private` and
//! `user_supplied_grok_rules`, and the Crush/Grok steps of
//! `run_once_with_wiring` (`contexts`) (2026-11-16). The client is
//! uds_http.rs.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

use ai_memory_core::ManagedRunContextResponse;
use ai_memory_workstream::{LaunchMode, LaunchPlan, ManagedHarness, crush_global_config_path};
use anyhow::{Context, Result};

use super::launch::Run;
use super::local::Local;
use super::uds_http::Client;

pub(crate) async fn fetch_grok_context(client: &Client, run_path: &str) -> Result<Option<String>> {
    let response: ManagedRunContextResponse = client
        .post_json(&format!("{run_path}/context"), &serde_json::json!({}))
        .await
        .context("loading the managed context for Grok; the agent was not started")?;
    Ok(response.context)
}

pub(crate) async fn prepare_crush_context(client: &Client, run_path: &str, source: &Path) -> Result<Option<tempfile::TempDir>> {
    let response: ManagedRunContextResponse = client
        .post_json(&format!("{run_path}/context"), &serde_json::json!({}))
        .await
        .context("loading the managed context for Crush; the agent was not started")?;
    let Some(context) = response.context else { return Ok(None) };
    write_crush_context_config(source, &context).map(Some)
}

/// The global `crush.json` the launched Crush reads, absolute.
pub(crate) fn crush_context_source(home: &Path, cwd: &Path, get: impl Fn(&str) -> Option<OsString>) -> PathBuf {
    cwd.join(crush_global_config_path(home, get))
}

/// A private config dir: the user's `crush.json` with the packet appended to
/// `options.global_context_paths` (seeded with Crush's own defaults while
/// empty), and a `crushrc` that sources the user's from its own folder.
pub(crate) fn write_crush_context_config(source: &Path, context: &str) -> Result<tempfile::TempDir> {
    let temp = tempfile::Builder::new().prefix("ai-memory-crush-").tempdir().context("creating the temporary Crush context directory")?;
    let context_path = temp.path().join("managed-workstream.md");
    write_private(&context_path, context.as_bytes())?;
    let source = ai_memory_workstream::clean_path(source);
    let raw = if source.is_file() {
        std::fs::read(&source).with_context(|| format!("reading Crush config {}", source.display()))?
    } else {
        Vec::new()
    };
    let mut config = if raw.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice::<serde_json::Value>(&raw).with_context(|| format!("parsing Crush config {}", source.display()))?
    };
    if config.is_null() {
        config = serde_json::json!({});
    }
    let root = config.as_object_mut().context("Crush global config must be a JSON object")?;
    let options = root.entry("options").or_insert(serde_json::Value::Null);
    if options.is_null() {
        *options = serde_json::json!({});
    }
    let options = options.as_object_mut().context("Crush global config `options` must be a JSON object")?;
    let paths = options.entry("global_context_paths").or_insert(serde_json::Value::Null);
    if paths.is_null() {
        *paths = serde_json::json!([]);
    }
    let paths = paths.as_array_mut().context("Crush `options.global_context_paths` must be an array")?;
    if paths.is_empty() && let Some(config_dir) = source.parent() {
        paths.push(serde_json::Value::String(config_dir.join("CRUSH.md").to_string_lossy().into_owned()));
        if let Some(parent) = config_dir.parent() {
            paths.push(serde_json::Value::String(parent.join("AGENTS.md").to_string_lossy().into_owned()));
        }
    }
    let context_path = context_path.to_string_lossy().into_owned();
    if !paths.iter().any(|value| value.as_str() == Some(&context_path)) {
        paths.push(serde_json::Value::String(context_path));
    }
    let rendered = serde_json::to_vec_pretty(&config).context("rendering Crush config")?;
    write_private(&temp.path().join("crush.json"), &rendered)?;
    if let Some(config_dir) = source.parent() {
        let crushrc = config_dir.join("crushrc");
        if crushrc.is_file() {
            let quote = |path: &Path| format!("'{}'", path.to_string_lossy().replace('\'', r"'\''"));
            let wrapper = format!("cd {} && source {}\n", quote(config_dir), quote(&crushrc));
            write_private(&temp.path().join("crushrc"), wrapper.as_bytes())?;
        }
    }
    Ok(temp)
}

/// Create `path` 0600, never over an existing file.
pub(crate) fn write_private(path: &Path, content: &[u8]) -> Result<()> {
    use std::io::Write as _;
    use std::os::unix::fs::OpenOptionsExt as _;
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
        .with_context(|| format!("creating {}", path.display()))?;
    file.write_all(content).with_context(|| format!("writing {}", path.display()))
}

/// The packet each harness takes outside its hooks, kept until the run ends.
pub(crate) struct Contexts {
    pub(crate) crush: Option<tempfile::TempDir>,
    pub(crate) grok: Option<String>,
}

/// Crush's config dir and Grok's `--rules` text for a session launch.
pub(crate) async fn contexts(local: &Local, run: &Run<'_>, plan: &LaunchPlan, native_grok_rules: bool) -> Result<Contexts> {
    let (client, run_path) = (&run.prep.client, run.prep.run_path.as_str());
    let session = plan.mode == LaunchMode::Session;
    let crush = if run.harness == ManagedHarness::Crush && session {
        let source = crush_context_source(&local.home, &local.repository.cwd, |name| local.child_env.lookup(name));
        prepare_crush_context(client, run_path, &source).await?
    } else {
        None
    };
    let grok = if run.harness == ManagedHarness::Grok && session {
        if native_grok_rules {
            eprintln!("ai-memory: --rules was supplied natively; the workstream context packet will be delivered on a later run");
            None
        } else {
            fetch_grok_context(client, run_path).await?
        }
    } else {
        None
    };
    Ok(Contexts { crush, grok })
}

/// `--rules` is single-use in Grok's parser: a user-supplied one wins.
pub(crate) fn user_supplied_grok_rules(native_args: &[OsString]) -> bool {
    native_args.iter().any(|arg| {
        arg.to_str().is_some_and(|value| {
            ["--rules", "--append-system-prompt"].iter().any(|name| value == *name || value.starts_with(&format!("{name}=")))
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_crush_config_keeps_user_settings_and_adds_the_packet() {
        let tmp = tempfile::tempdir().unwrap();
        let source = tmp.path().join("crush/crush.json");
        std::fs::create_dir_all(source.parent().unwrap()).unwrap();
        std::fs::write(&source, r#"{"models":{"large":"x"}}"#).unwrap();
        std::fs::write(tmp.path().join("crush/crushrc"), "true\n").unwrap();
        let dir = write_crush_context_config(&source, "packet").unwrap();
        let config: serde_json::Value = serde_json::from_slice(&std::fs::read(dir.path().join("crush.json")).unwrap()).unwrap();
        assert_eq!(config["models"]["large"], "x");
        let paths = config["options"]["global_context_paths"].as_array().unwrap();
        assert_eq!(paths.len(), 3);
        assert!(paths[2].as_str().unwrap().ends_with("managed-workstream.md"));
        assert!(std::fs::read_to_string(dir.path().join("crushrc")).unwrap().starts_with("cd '"));
        assert!(user_supplied_grok_rules(&["--rules=x".into()]));
        assert!(!user_supplied_grok_rules(&["--rulesx".into()]));
    }
}
