//! Claude's automatic memory index, owned by Cadex (plan 22, phase C, "A
//! memória automática do Claude"). Each session Cadex opens saves its
//! memories in `<memory>/auto/…/<project key>/` (`autoMemoryDirectory`): one
//! topic file per memory (frontmatter `name`, `description`) and MEMORY.md,
//! the index Claude loads at start (its first 200 lines / 25 KB). Claude
//! rewrites MEMORY.md whole, so the last of several sessions saving at once
//! wins: with 4 simultaneous sessions, all 4 topic files were there and the
//! index had 1 entry (tested 2026-11-14, Claude Code 2.1.325). Here the
//! index is rebuilt from the topic files after every change:
//! - every existing line stays, in its order, except a link to a topic file
//!   that is gone;
//! - each topic file no line links to gets `- [<name>](<file>) — <description>`,
//!   the new ones by modification time, oldest first;
//! - over 200 lines or 25,000 bytes, the entries (lines linking to a topic
//!   file) of the oldest topic files go first; other lines, written by hand,
//!   never do.

use std::path::{Path, PathBuf};
use std::time::SystemTime;

use anyhow::Result;

pub(crate) const INDEX: &str = "MEMORY.md";
/// What Claude Code loads of MEMORY.md (its documentation, 2026-11-14):
/// the first 200 lines, up to 25 KB; 25,000 bytes keeps under either reading.
const MAX_LINES: usize = 200;
const MAX_BYTES: usize = 25_000;

/// One memory Claude saved.
#[derive(Debug, Clone)]
pub(crate) struct Topic {
    /// The file's name in the folder (`feedback_tests.md`).
    pub(crate) file: String,
    pub(crate) name: String,
    pub(crate) description: Option<String>,
    /// `originSessionId` from the frontmatter: the session that saved it.
    pub(crate) origin_session: Option<String>,
    /// The text after the frontmatter.
    pub(crate) body: String,
    pub(crate) modified: SystemTime,
    /// The whole file, for the wiki's unchanged check (auto_wiki.rs).
    pub(crate) raw: String,
}

/// A frontmatter value: one line, quotes taken off.
fn unquote(value: &str) -> String {
    let v = value.trim();
    let quoted = v.len() >= 2 && ((v.starts_with('"') && v.ends_with('"')) || (v.starts_with('\'') && v.ends_with('\'')));
    if quoted { v[1..v.len() - 1].to_string() } else { v.to_string() }
}

/// The frontmatter's top-level `key: value` lines and the body after it.
fn split_frontmatter(text: &str) -> (Vec<(String, String)>, &str) {
    let Some(rest) = text.strip_prefix("---\n").or_else(|| text.strip_prefix("---\r\n")) else {
        return (Vec::new(), text);
    };
    let Some(end) = rest.find("\n---") else { return (Vec::new(), text) };
    let fields = rest[..end]
        .lines()
        .filter(|l| !l.starts_with([' ', '\t']))
        .filter_map(|l| l.split_once(':'))
        .map(|(k, v)| (k.trim().to_string(), unquote(v)))
        .collect();
    let body = rest[end + 4..].trim_start_matches(['\r', '\n']);
    (fields, body)
}

/// A topic file read; `None` for one that is not (a vanished file).
pub(crate) fn read_topic(path: &Path) -> Option<Topic> {
    let raw = std::fs::read_to_string(path).ok()?;
    let modified = std::fs::metadata(path).and_then(|m| m.modified()).unwrap_or(SystemTime::UNIX_EPOCH);
    let file = path.file_name()?.to_str()?.to_string();
    let (fields, body) = split_frontmatter(&raw);
    let field = |key: &str| fields.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone()).filter(|v| !v.is_empty());
    Some(Topic {
        name: field("name").unwrap_or_else(|| file.trim_end_matches(".md").to_string()),
        description: field("description"),
        origin_session: field("originSessionId"),
        body: body.to_string(),
        modified,
        file,
        raw: raw.clone(),
    })
}

/// Whether `name` is a topic file of an automatic memory folder.
pub(crate) fn is_topic_name(name: &str) -> bool {
    name.ends_with(".md") && name != INDEX && !name.starts_with('.')
}

/// The folder's topic files, oldest first.
pub(crate) fn topics(dir: &Path) -> Vec<Topic> {
    let Ok(entries) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut found: Vec<Topic> = entries
        .flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_file()))
        .filter(|e| e.file_name().to_str().is_some_and(is_topic_name))
        .filter_map(|e| read_topic(&e.path()))
        .collect();
    found.sort_by(|a, b| a.modified.cmp(&b.modified).then_with(|| a.file.cmp(&b.file)));
    found
}

/// The file a `- [title](target)` line links to, when it is a local one.
fn link_target(line: &str) -> Option<&str> {
    let rest = line.trim_start().strip_prefix(['-', '*'])?.trim_start();
    let title_and_rest = rest.strip_prefix('[')?;
    let after_title = &title_and_rest[title_and_rest.find("](")? + 2..];
    let target = after_title[..after_title.find(')')?].trim();
    let target = target.strip_prefix("./").unwrap_or(target);
    (target.ends_with(".md") && !target.contains("://")).then_some(target)
}

fn one_line(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn entry(topic: &Topic) -> String {
    let name = one_line(&topic.name).replace(']', ")");
    match &topic.description {
        Some(d) => format!("- [{name}]({}) — {}", topic.file, one_line(d)),
        None => format!("- [{name}]({})", topic.file),
    }
}

/// The index for `existing` and the folder's `topics` (oldest first);
/// `exists` says whether a linked file is still in the folder.
pub(crate) fn rebuild(existing: &str, topics: &[Topic], exists: impl Fn(&str) -> bool) -> String {
    // Each line with, for an entry, its topic's age rank (0 = oldest).
    let rank = |file: &str| topics.iter().position(|t| t.file == file).unwrap_or(usize::MAX);
    let mut lines: Vec<(String, Option<usize>)> = Vec::new();
    for line in existing.lines() {
        match link_target(line) {
            Some(target) if !exists(target) => continue,
            Some(target) => lines.push((line.to_string(), Some(rank(target)))),
            None => lines.push((line.to_string(), None)),
        }
    }
    while lines.last().is_some_and(|(l, _)| l.trim().is_empty()) {
        lines.pop();
    }
    for (i, topic) in topics.iter().enumerate() {
        if !existing.lines().filter_map(link_target).any(|t| t == topic.file) {
            lines.push((entry(topic), Some(i)));
        }
    }
    let size = |lines: &[(String, Option<usize>)]| lines.iter().map(|(l, _)| l.len() + 1).sum::<usize>();
    while lines.len() > MAX_LINES || size(&lines) > MAX_BYTES {
        let oldest = lines.iter().enumerate().filter_map(|(i, (_, r))| r.map(|r| (r, i))).min();
        let Some((_, at)) = oldest else { break };
        lines.remove(at);
    }
    lines.into_iter().map(|(l, _)| l + "\n").collect()
}

/// How many times a rebuild starts over when MEMORY.md changed under it.
const REBUILD_TRIES: usize = 5;

/// Rebuild `dir`'s MEMORY.md; returns the text written, or `None` when it
/// was already right (nothing written, so no event of ours to follow).
/// Claude may write the index while it is rebuilt: the file is read again
/// just before the write, and a change starts the rebuild over, so the
/// write that could still be lost is one landing between that read and the
/// rename (microseconds). Without it, a session's index written during a
/// rebuild was replaced, and its event then looked like ours and was
/// skipped (tests/auto_memory.rs, 1 failure in 12 loaded runs, 2026-11-16).
pub(crate) fn rebuild_folder(dir: &Path) -> Result<Option<String>> {
    let path = dir.join(INDEX);
    let read = || std::fs::read_to_string(&path).unwrap_or_default();
    let mut existing = read();
    for _ in 0..REBUILD_TRIES {
        let text = rebuild(&existing, &topics(dir), |file| dir.join(file).is_file());
        if text == existing {
            return Ok(None);
        }
        let now = read();
        if now != existing {
            existing = now;
            continue;
        }
        write_atomically(&path, &text)?;
        return Ok(Some(text));
    }
    anyhow::bail!("MEMORY.md kept changing; rebuilt at its next change")
}

/// Write beside and rename over: Claude never reads half an index.
fn write_atomically(path: &Path, text: &str) -> Result<()> {
    let tmp: PathBuf = path.with_file_name(format!(".{INDEX}.cadex-{}.tmp", std::process::id()));
    std::fs::write(&tmp, text)?;
    if let Err(e) = std::fs::rename(&tmp, path) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn topic(dir: &Path, file: &str, name: &str, description: &str) {
        let text = format!("---\nname: {name}\ndescription: \"{description}\"\nmetadata:\n  type: feedback\noriginSessionId: s-{file}\n---\n\nBody of {name}.\n");
        std::fs::write(dir.join(file), text).unwrap();
    }

    #[test]
    fn four_topics_saved_at_once_all_get_an_entry() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path();
        for i in 1..=4 {
            topic(dir, &format!("t{i}.md"), &format!("Topic {i}"), &format!("hook {i}"));
        }
        // The last of the four sessions wrote the index: one entry left.
        std::fs::write(dir.join(INDEX), "- [Topic 4](t4.md) — Claude's own words\n").unwrap();
        let text = rebuild_folder(dir).unwrap().expect("rewritten");
        assert_eq!(text.lines().count(), 4, "{text}");
        assert!(text.starts_with("- [Topic 4](t4.md) — Claude's own words\n"), "the existing line first, as written");
        for i in 1..=3 {
            assert!(text.contains(&format!("- [Topic {i}](t{i}.md) — hook {i}")), "{text}");
        }
        assert!(rebuild_folder(dir).unwrap().is_none(), "nothing to do the second time");
        let t = read_topic(&dir.join("t1.md")).unwrap();
        assert_eq!(t.origin_session.as_deref(), Some("s-t1.md"));
        assert_eq!(t.body, "Body of Topic 1.\n");
    }

    #[test]
    fn hand_written_lines_stay_and_links_to_missing_files_go() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path();
        topic(dir, "kept.md", "Kept", "still here");
        let existing = "# My notes\n\nRemember the staging box.\n- [Gone](gone.md) — deleted\n- [Kept](./kept.md) — mine\n- [Docs](https://example.com/x.md)\n";
        std::fs::write(dir.join(INDEX), existing).unwrap();
        let text = rebuild_folder(dir).unwrap().unwrap();
        assert_eq!(text, "# My notes\n\nRemember the staging box.\n- [Kept](./kept.md) — mine\n- [Docs](https://example.com/x.md)\n");
    }

    #[test]
    fn over_the_caps_the_oldest_entries_go_never_the_hand_written_lines() {
        let at = |s: u64| SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(s);
        let topics: Vec<Topic> = (0..250)
            .map(|i| Topic {
                file: format!("t{i:03}.md"), name: format!("T{i}"), description: Some("d".into()),
                origin_session: None, body: String::new(), modified: at(i), raw: String::new(),
            })
            .collect();
        let text = rebuild("# Hand\nnote\n", &topics, |_| true);
        assert_eq!(text.lines().count(), 200);
        assert!(text.starts_with("# Hand\nnote\n") && text.contains("(t249.md)") && !text.contains("(t051.md)"));
        assert!(text.contains("(t052.md)"), "only as many as needed went");

        let long = "x".repeat(400);
        let wide: Vec<Topic> = topics.iter().take(100).cloned().map(|mut t| { t.description = Some(long.clone()); t }).collect();
        let text = rebuild("# Hand\n", &wide, |_| true);
        assert!(text.len() <= MAX_BYTES && text.starts_with("# Hand\n") && text.contains("(t099.md)"));
        assert!(!text.contains("(t000.md)"));
    }
}
