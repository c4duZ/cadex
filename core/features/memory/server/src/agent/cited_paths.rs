//! The repository paths an auto-improve proposal cites, and whether any of
//! them exists (plan 35 phase G, 2026-11-19).
//!
//! **Why.** The bkdg-center case (2026-11-18): session 98ee49fa began at the
//! Center's root and worked in another folder (not a repository); its review
//! wrote four pages about a system that does not exist in the Center, cited by
//! paths the Center does not have, and they were approved on their own.
//! Upstream has no such check (docs/research/ai-memory-upstream.md, point 3),
//! so it is Cadex's, in front of the staging (improve.rs).
//!
//! **The rule, kept conservative.** A proposal that cites at least one path
//! and none of whose cited paths exists under the project's main root is
//! refused. A cited path is a token with a slash and a known code extension
//! (`src/cache.rs`), a backticked token with a known extension
//! (`Cargo.toml`), or a backticked folder (`app/models/`, `a/b/c`). Markdown
//! files count only as found: a `.md` the repository has shows the proposal
//! is about it, one it lacks may be a wiki page. URLs, absolute paths outside
//! the root, `~` paths, globs and placeholders are not paths here. A path is
//! found at the root or, failing that, as the tail of a file git knows (a
//! proposal may cite `models/user.rb` for `app/models/user.rb`). Tables and
//! identifiers are not checked: too easy to get wrong.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::Command;

use ai_memory_consolidate::AutoImproveReport;
use ai_memory_core::SessionId;
use tracing::warn;

use super::jobs::Step;

/// Code and config extensions a cited path may end with.
const EXTENSIONS: &[&str] = &[
    "rs", "swift", "zig", "go", "py", "rb", "erb", "rake", "js", "jsx", "mjs", "cjs", "ts", "tsx", "vue", "svelte",
    "java", "kt", "kts", "scala", "c", "h", "cc", "cpp", "hpp", "m", "mm", "cs", "php", "ex", "exs", "dart", "lua",
    "sql", "sh", "bash", "zsh", "fish", "toml", "yaml", "yml", "json", "jsonc", "xml", "html", "css", "scss", "sass",
    "proto", "graphql", "gql", "tf", "gradle", "plist", "xcconfig", "lock", "ini", "cfg", "conf", "env", "csv", "md",
    "mdx", "txt",
];

/// A path a proposal cites, and whether only a hit counts (Markdown).
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) struct Cited {
    pub(crate) path: String,
    pub(crate) hit_only: bool,
}

/// The paths `text` cites, in order, without repeats.
pub(crate) fn cited(text: &str, root: &Path) -> Vec<Cited> {
    let mut out = BTreeSet::new();
    let mut rest = text;
    while let Some(start) = rest.find('`') {
        words(&rest[..start], false, root, &mut out);
        let after = &rest[start..];
        let ticks = after.len() - after.trim_start_matches('`').len();
        let inner = &after[ticks..];
        let fence = "`".repeat(ticks);
        let Some(end) = inner.find(fence.as_str()) else {
            words(inner, false, root, &mut out);
            rest = "";
            break;
        };
        let span = &inner[..end];
        let one_token = ticks < 3 && !span.trim().contains(char::is_whitespace);
        words(span, one_token, root, &mut out);
        rest = &inner[end + ticks..];
    }
    words(rest, false, root, &mut out);
    out.into_iter().collect()
}

fn words(text: &str, ticked: bool, root: &Path, out: &mut BTreeSet<Cited>) {
    let separators = |c: char| c.is_whitespace() || "()[]{}<>\"'|,;=".contains(c);
    for word in text.split(separators) {
        if let Some(c) = path_of(word, ticked, root) {
            out.insert(c);
        }
    }
}

fn path_of(word: &str, ticked: bool, root: &Path) -> Option<Cited> {
    let mut w = word.trim_matches(|c: char| ".,:;!?*_".contains(c));
    if w.is_empty() || w.contains("://") || w.starts_with(['~', '-', '$', '@', '#']) || w.contains(['*', '?', '\\']) {
        return None;
    }
    if let Some(stripped) = w.strip_prefix('/') {
        let root = root.to_str()?.trim_start_matches('/');
        w = stripped.strip_prefix(root)?.trim_start_matches('/');
    }
    let w = line_suffix_cut(w.trim_start_matches("./"));
    let segments: Vec<&str> = w.trim_end_matches('/').split('/').collect();
    if segments.iter().any(|s| s.is_empty() || *s == "..") || !w.chars().any(char::is_alphabetic) {
        return None;
    }
    let ext = segments.last()?.rsplit_once('.').map(|(stem, ext)| (stem, ext.to_ascii_lowercase()));
    let known = ext.as_ref().is_some_and(|(stem, ext)| !stem.is_empty() && EXTENSIONS.contains(&ext.as_str()));
    let slashes = segments.len() - 1;
    let is_path = if known { slashes > 0 || ticked } else { ticked && (w.ends_with('/') || slashes >= 2) };
    is_path.then(|| Cited { path: w.trim_end_matches('/').to_owned(), hit_only: ext.is_some_and(|(_, e)| e == "md" || e == "mdx") })
}

/// `src/a.rs:42`, `src/a.rs:42:7` and `src/a.rs#L42` are `src/a.rs`.
fn line_suffix_cut(w: &str) -> &str {
    let w = w.split_once("#L").map_or(w, |(p, _)| p);
    let mut w = w;
    while let Some((head, tail)) = w.rsplit_once(':') {
        if tail.is_empty() || tail.chars().all(|c| c.is_ascii_digit()) {
            w = head;
        } else {
            break;
        }
    }
    w
}

/// The files of a repository, read once when a path is not at its root.
pub(crate) struct Repo {
    root: PathBuf,
    tracked: Option<Vec<String>>,
}

impl Repo {
    pub(crate) fn new(root: PathBuf) -> Self {
        Self { root, tracked: None }
    }

    /// Whether `path` is in the repository: at the root, or the tail of a
    /// file git knows (or of its folder).
    pub(crate) fn has(&mut self, path: &str) -> bool {
        if self.root.join(path).exists() {
            return true;
        }
        let root = self.root.clone();
        let tracked = self.tracked.get_or_insert_with(|| git_files(&root));
        let (tail, inner) = (format!("/{path}"), format!("/{path}/"));
        tracked.iter().any(|f| f.ends_with(&tail) || f.starts_with(&inner[1..]) || f.contains(&inner))
    }

    /// When the proposal must be refused: the paths it cites, none found.
    pub(crate) fn refusal(&mut self, texts: &[&str]) -> Option<Vec<String>> {
        let mut cited: Vec<Cited> = texts.iter().flat_map(|t| cited(t, &self.root)).collect();
        cited.sort();
        cited.dedup();
        if cited.iter().any(|c| self.has(&c.path)) {
            return None;
        }
        let missing: Vec<String> = cited.into_iter().filter(|c| !c.hit_only).map(|c| c.path).collect();
        (!missing.is_empty()).then_some(missing)
    }
}

/// The report without the proposals that cite only paths the
/// project's repository lacks, each with a ledger line and a
/// warning on the run. The bkdg-center case (2026-11-18): a session that
/// worked in another folder became four approved pages about a system the
/// Center does not have (plan 35 G). With no root known, nothing is refused.
pub(crate) async fn refuse_foreign(step: &Step<'_>, session_id: Option<SessionId>, report: &AutoImproveReport, trigger: &str) -> AutoImproveReport {
    let mut report = report.clone();
    let Some(root) = step.job.scope.root.clone().filter(|r| r.is_dir()) else { return report };
    let texts: Vec<Vec<String>> = report
        .proposals
        .iter()
        .map(|p| [p.title.clone(), p.body_markdown.clone()].into_iter().chain(p.edits.iter().map(|e| e.content.clone())).collect())
        .collect();
    let verdicts = tokio::task::spawn_blocking(move || {
        let mut repo = Repo::new(root);
        texts.iter().map(|t| repo.refusal(&t.iter().map(String::as_str).collect::<Vec<_>>())).collect::<Vec<_>>()
    })
    .await
    .unwrap_or_default();
    let kind = if trigger == "scheduler" { "auto-improve" } else { "experience" };
    let mut verdicts = verdicts.into_iter();
    let mut refused = Vec::new();
    report.proposals.retain(|p| match verdicts.next().flatten() {
        Some(missing) => {
            refused.push(format!("refused {}: cites only paths not in the repository: {}", p.path, missing.join(", ")));
            false
        }
        None => true,
    });
    for why in refused {
        warn!(%why, "auto-improve proposal refused");
        step.note_about(kind, session_id.map(|id| id.to_string()), true, &why);
        report.warnings.push(format!("cadex: {why}"));
    }
    report
}

/// `git ls-files` at `root` (tracked files, relative); nothing when git fails.
fn git_files(root: &Path) -> Vec<String> {
    let out = Command::new("git").arg("-C").arg(root).args(["ls-files", "-z"]).output();
    match out {
        Ok(out) if out.status.success() => {
            String::from_utf8_lossy(&out.stdout).split('\0').filter(|s| !s.is_empty()).map(str::to_owned).collect()
        }
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths(text: &str) -> Vec<String> {
        cited(text, Path::new("/repo/acme")).into_iter().map(|c| c.path).collect()
    }

    #[test]
    fn paths_are_found_and_prose_is_not() {
        let text = "Edit `src/cache.rs:42` and app/models/user.rb, see [x](lib/a.ts#L3). \
                    Not and/or, HTTP/1.1, text/html, https://x.io/a.rs, ~/.zshrc, `*.rs` or `<id>/x.rs`. \
                    Folder `app/services/` and `a/b/c`, file `Cargo.toml`, bare Cargo.toml, /repo/acme/src/x.rs, /etc/hosts.conf.";
        assert_eq!(paths(text), [
            "Cargo.toml", "a/b/c", "app/models/user.rb", "app/services", "lib/a.ts", "src/cache.rs", "src/x.rs",
        ]);
    }

    #[test]
    fn a_fence_is_read_as_prose() {
        assert_eq!(paths("```sh\ncat config/db.yml\n```\nthen `x`"), ["config/db.yml"]);
    }

    #[test]
    fn a_proposal_is_refused_only_when_no_cited_path_exists() {
        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(tmp.path().join("app/models")).unwrap();
        std::fs::write(tmp.path().join("app/models/user.rb"), "").unwrap();
        std::fs::write(tmp.path().join("README.md"), "").unwrap();
        let mut repo = Repo::new(tmp.path().to_owned());
        assert_eq!(repo.refusal(&["see `app/competencias/ciclo.rb`"]), Some(vec!["app/competencias/ciclo.rb".into()]));
        assert_eq!(repo.refusal(&["see `app/competencias/ciclo.rb` and app/models/user.rb"]), None);
        assert_eq!(repo.refusal(&["no paths at all"]), None);
        assert_eq!(repo.refusal(&["a wiki page `gotchas/wal-lock.md`"]), None, "a missing .md may be a wiki page");
        assert_eq!(repo.refusal(&["`README.md` and `lib/gone.rs`"]), None, "a .md the repository has counts");
    }
}
