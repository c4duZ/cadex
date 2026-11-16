//! `cadex-memory export-plugin <dir>`: the Claude Code plugin with
//! upstream's own routing skills (`ai_memory_core::routing_skills`, the same
//! `SKILL.md` bytes its installer writes), which the session kit passes by
//! `--plugin-dir` (plan 22 phase D: "quando buscar, quando salvar, quando
//! abrir um handoff"). Taken from the crate at build time, so a new upstream
//! commit brings its new skills with no copy in this repository.
//!
//! Left out, like their tools in `cadex mcp` (core/features/memory/
//! mcp_proxy.zig): learning-maintenance (consolidation, sweeps and
//! auto-improvement, which need a provider or an administrator) and
//! routing-install (writing CLAUDE.md or skills into the owner's folders,
//! which Cadex never does).

use std::path::Path;

use anyhow::{Context, Result};
use ai_memory_core::routing_skills::MANAGED_SKILLS;

/// The skills the plugin carries.
pub(crate) const OFFERED: [&str; 4] =
    ["ai-memory-retrieval", "ai-memory-durable-pages", "ai-memory-handoff", "ai-memory-messaging"];

const MANIFEST: &str = concat!(
    "{\n  \"name\": \"cadex-memory\",\n",
    "  \"description\": \"The project memory Cadex keeps with ai-memory: search it, save to it, continue from a handoff.\",\n",
    "  \"version\": \"", env!("CARGO_PKG_VERSION"), "\"\n}\n"
);

/// Writes the plugin into `dir` (created), replacing what is there.
pub(crate) fn export(dir: &Path) -> Result<()> {
    let skills_dir = dir.join("skills");
    if skills_dir.exists() {
        std::fs::remove_dir_all(&skills_dir).context("clear the old skills")?;
    }
    std::fs::create_dir_all(dir.join(".claude-plugin"))?;
    std::fs::write(dir.join(".claude-plugin/plugin.json"), MANIFEST)?;
    for name in OFFERED {
        let skill = MANAGED_SKILLS.iter().find(|s| s.name == name).with_context(|| format!("upstream has no skill {name}"))?;
        let target = skills_dir.join(name);
        std::fs::create_dir_all(&target)?;
        std::fs::write(target.join("SKILL.md"), skill.content)?;
    }
    Ok(())
}

pub(crate) fn run(argv: &[String]) -> Result<()> {
    let [dir] = argv else { anyhow::bail!("usage: cadex-memory export-plugin <dir>") };
    export(Path::new(dir))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_plugin_holds_upstreams_skills_as_they_are() {
        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(tmp.path().join("skills/stale")).unwrap();
        export(tmp.path()).unwrap();
        let manifest: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(tmp.path().join(".claude-plugin/plugin.json")).unwrap()).unwrap();
        assert_eq!(manifest["name"], "cadex-memory");
        assert!(!tmp.path().join("skills/stale").exists());
        for name in OFFERED {
            let text = std::fs::read_to_string(tmp.path().join("skills").join(name).join("SKILL.md")).unwrap();
            assert!(text.starts_with("---\nname: ") && text.contains(name), "{name}");
        }
    }
}
