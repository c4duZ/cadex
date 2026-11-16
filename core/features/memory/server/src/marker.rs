//! A repository's `.ai-memory.toml`, found and read the way upstream's hook
//! client does: the engine reads it from the event's `cwd`, since in Cadex
//! the hook client is `cadex memory-hook` (Zig) and not upstream's CLI
//! (plan 22, real-session test of 2026-11-16: the brief named a file Cadex
//! ignored).
//!
//! Copied from upstream's `crates/ai-memory-cli/src/marker.rs` at
//! fa0ec25dbe987b7574a7487ecf92f0873040c2f2 (MIT, Fábio Akita), whose crate
//! Cadex does not build: `find_marker_matching`, `checkout_root`,
//! `absolute_normalized`, `lexically_normalize`, `declares_more_than_capture`
//! and the line parsers, unchanged but for `pub(crate)` and the cut parts:
//! the home routes (`[[route]]` in `~/.ai-memory.toml`), the server profiles
//! (`server = …`, kept only as a boundary) and the walk to the filesystem
//! root that only server selection uses. The `[capture]` reader is upstream's
//! `read_capture_config_verbose` (hook_capture.rs) on `toml`, already in the
//! lock, instead of `toml_edit`, which is not.

use std::io::Read;
use std::path::{Component, Path, PathBuf};

use ai_memory_hooks::CaptureConfig;
use ai_memory_hooks::capture_policy::MAX_MARKER_BYTES;

pub(crate) const MARKER_FILENAME: &str = ".ai-memory.toml";

pub(crate) fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME").filter(|h| !h.is_empty()).map(PathBuf::from)
}

/// The nearest marker walking up from `cwd`: to `$HOME` inside it, to the
/// checkout root outside it (`cwd` alone outside any checkout).
pub(crate) fn find_marker(cwd: &str, home: Option<&Path>) -> Option<PathBuf> {
    find_marker_matching(cwd, home, |path| Some(path.to_path_buf()))
}

/// Like [`find_marker`], but a marker with nothing beyond `[capture]` is
/// transparent: the walk goes on to the next one (upstream #668). The home
/// marker always stops the walk.
pub(crate) fn find_settings_marker(cwd: &str, home: Option<&Path>) -> Option<PathBuf> {
    let home_marker = home.map(|home| absolute_normalized(&home.join(MARKER_FILENAME)));
    find_marker_matching(cwd, home, |path| {
        if home_marker.as_ref().is_some_and(|marker| absolute_normalized(path) == *marker) {
            return Some(path.to_path_buf());
        }
        std::fs::read_to_string(path)
            .is_ok_and(|text| declares_more_than_capture(&text))
            .then(|| path.to_path_buf())
    })
}

fn find_marker_matching<T>(
    cwd: &str,
    home: Option<&Path>,
    mut matches: impl FnMut(&Path) -> Option<T>,
) -> Option<T> {
    let start = absolute_normalized(Path::new(cwd));
    let home = home.map(absolute_normalized);
    let boundary = match home.as_deref() {
        Some(home) if start.starts_with(home) => Some(home.to_path_buf()),
        Some(_) => Some(checkout_root(&start).unwrap_or_else(|| start.clone())),
        None => None,
    };
    let mut dir = start.as_path();
    loop {
        let candidate = dir.join(MARKER_FILENAME);
        if candidate.is_file()
            && let Some(found) = matches(&candidate)
        {
            return Some(found);
        }
        if boundary.as_deref() == Some(dir) {
            return None;
        }
        match dir.parent() {
            Some(parent) if parent != dir => dir = parent,
            _ => return None,
        }
    }
}

/// Whether the text declares any key the hook forwards; a stray key under
/// any table counts, which can only make a marker a boundary (upstream).
fn declares_more_than_capture(text: &str) -> bool {
    const QUOTED_KEYS: [&str; 6] =
        ["workspace", "project", "project_strategy", "drop_subagent_captures", "identity", "identity_style"];
    const FLAG_KEYS: [&str; 9] = [
        "default_global",
        "inject_on_session_start",
        "inject_on_subagent_start",
        "max_chars",
        "contribute",
        "consume",
        "deliver_on_session_start",
        "inbox_notice_on_prompt",
        "server",
    ];
    QUOTED_KEYS.iter().any(|key| parse_key_in(text, key).is_some())
        || FLAG_KEYS.iter().any(|key| parse_flag_in(text, key).is_some())
        || text.lines().any(|line| {
            line.trim_start_matches('\u{feff}')
                .trim_start()
                .strip_prefix("aliases")
                .is_some_and(|rest| rest.trim_start().starts_with('='))
        })
}

/// Absolute and `.`/`..`-free without touching the disk: the marker's
/// directory and the payload's paths stay in the same namespace (upstream
/// #671, macOS `/var` vs `/private/var`).
pub(crate) fn absolute_normalized(path: &Path) -> PathBuf {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().map(|cwd| cwd.join(path)).unwrap_or_else(|_| path.to_path_buf())
    };
    lexically_normalize(&absolute)
}

fn lexically_normalize(path: &Path) -> PathBuf {
    let mut stack: Vec<Component<'_>> = Vec::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => match stack.last() {
                Some(Component::Normal(_)) => {
                    stack.pop();
                }
                Some(Component::RootDir | Component::Prefix(_)) => {}
                _ => stack.push(component),
            },
            other => stack.push(other),
        }
    }
    stack.into_iter().collect()
}

fn checkout_root(start: &Path) -> Option<PathBuf> {
    let mut dir = start;
    loop {
        if dir.join(".git").exists() {
            return Some(dir.to_path_buf());
        }
        match dir.parent() {
            Some(parent) if parent != dir => dir = parent,
            _ => return None,
        }
    }
}

/// A root-level `key = "value"`; the first match, section headers ignored.
pub(crate) fn parse_key_in(text: &str, key: &str) -> Option<String> {
    for line in text.lines() {
        let trimmed = line.trim_start_matches('\u{feff}').trim_start();
        let Some(after_key) = trimmed.strip_prefix(key) else { continue };
        let Some(rest) = after_key.trim_start().strip_prefix('=') else { continue };
        let Some(rest) = rest.trim_start().strip_prefix('"') else { continue };
        if let Some(end) = rest.find('"') {
            return Some(rest[..end].to_string());
        }
    }
    None
}

/// `key = value`, quoted or bare, with a trailing `# comment` cut.
pub(crate) fn parse_flag_in(text: &str, key: &str) -> Option<String> {
    text.lines().find_map(|line| parse_flag_line(line, key))
}

fn parse_flag_line(line: &str, key: &str) -> Option<String> {
    let trimmed = line.trim_start_matches('\u{feff}').trim_start();
    let after_key = trimmed.strip_prefix(key)?;
    let rest = after_key.trim_start().strip_prefix('=')?;
    let val = rest.split('#').next().unwrap_or("").trim().trim_matches('"');
    (!val.is_empty()).then(|| val.to_string())
}

/// A flag inside one table (`exclude == false`) or outside it (`true`):
/// `[recovery] deliver_on_session_start` and the `[handoff]` one share a key.
pub(crate) fn parse_scoped_flag_in(text: &str, section: &str, key: &str, exclude: bool) -> Option<String> {
    let mut in_section = false;
    for line in text.lines() {
        let trimmed = line.trim_start_matches('\u{feff}').trim();
        let header = trimmed.split('#').next().unwrap_or("").trim();
        if let Some(name) = header.strip_prefix('[').and_then(|header| header.strip_suffix(']')) {
            in_section = name.trim() == section;
            continue;
        }
        if in_section == exclude {
            continue;
        }
        if let Some(value) = parse_flag_line(line, key) {
            return Some(value);
        }
    }
    None
}

pub(crate) fn is_falsy(value: &str) -> bool {
    matches!(value.trim().to_ascii_lowercase().as_str(), "0" | "false" | "no" | "off")
}

/// The marker's strict `[capture]` table; `Err` fails closed upstream
/// (every file and shell event kept as metadata only).
pub(crate) fn read_capture_config(marker: &Path) -> Result<CaptureConfig, String> {
    let mut bytes = Vec::with_capacity(MAX_MARKER_BYTES + 1);
    std::fs::File::open(marker)
        .map_err(|e| format!("could not open marker file: {e}"))?
        .take((MAX_MARKER_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|e| format!("could not read marker file: {e}"))?;
    if bytes.len() > MAX_MARKER_BYTES {
        return Err(format!("marker file is larger than the {MAX_MARKER_BYTES}-byte capture-config limit"));
    }
    let text = String::from_utf8(bytes).map_err(|e| format!("marker file is not valid UTF-8: {e}"))?;
    let document: toml::Table = text.parse().map_err(|e| format!("invalid TOML: {e}"))?;
    let Some(capture) = document.get("capture") else { return Ok(CaptureConfig::default()) };
    let table = capture.as_table().ok_or("`[capture]` must be a table")?;
    if let Some(key) = table.keys().find(|key| *key != "ignore_paths") {
        return Err(format!("`[capture]` has an unsupported key `{key}` (only `ignore_paths` is allowed)"));
    }
    let ignore_paths = match table.get("ignore_paths") {
        None => Vec::new(),
        Some(item) => item
            .as_array()
            .ok_or("`[capture].ignore_paths` must be an array")?
            .iter()
            .map(|value| value.as_str().map(str::to_owned).ok_or("`[capture].ignore_paths` must contain only strings"))
            .collect::<Result<Vec<_>, _>>()?,
    };
    Ok(CaptureConfig { ignore_paths })
}
