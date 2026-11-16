//! Claude's automatic memory folders (plan 22, phase C): four topic files
//! saved at once leave four entries in MEMORY.md and four wiki pages; an
//! edit updates its page, a deletion removes its page and its entry; what
//! changed while the engine was down is reconciled when it starts.

mod common;

use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

use common::{repo, start, tool};
use sha2::{Digest, Sha256};

/// The folder the app gives the project (project_key.rs, MemoryProject.swift).
fn auto_folder(data: &Path, root: &Path) -> PathBuf {
    let dir = data.join("auto").join(key(root));
    std::fs::create_dir_all(&dir).unwrap();
    project_json(&dir, root);
    dir
}

fn key(root: &Path) -> String {
    let digest = Sha256::digest(root.canonicalize().unwrap().to_str().unwrap().as_bytes());
    digest.iter().take(8).map(|b| format!("{b:02x}")).collect()
}

fn project_json(dir: &Path, root: &Path) {
    let json = serde_json::json!({"root": root.canonicalize().unwrap(), "account": null});
    std::fs::write(dir.join("project.json"), json.to_string()).unwrap();
}

fn topic(dir: &Path, i: usize, extra: &str) {
    let text = format!("---\nname: Topic {i}\ndescription: hook {i}\nmetadata:\n  type: project\noriginSessionId: 0000000{i}-0000-4000-8000-000000000000\n---\n\nThe albatross{i} fact{extra}.\n");
    std::fs::write(dir.join(format!("t{i}.md")), text).unwrap();
}

fn wait_for(what: &str, mut ok: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if ok() {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for {what}");
}

fn index(dir: &Path) -> String {
    std::fs::read_to_string(dir.join("MEMORY.md")).unwrap_or_default()
}

fn page(socket: &Path, file: &str) -> String {
    tool(socket, "memory_read_page", serde_json::json!({
        "workspace": "default", "project": "acme", "path": format!("auto/{file}"),
    }))
}

#[test]
fn four_memories_saved_at_once_are_all_indexed_and_in_the_wiki() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let engine = start(tmp.path(), &["--keep-alive"]);
    // Four topic files and the index the last of the four sessions left,
    // with only its own entry, appear at once: made beside and moved in by
    // one rename. Written one by one, the engine could rebuild between the
    // writes, which is the case auto_index.rs `rebuild_folder` handles, not
    // a state this test can wait on.
    let staged = tmp.path().join("staged");
    std::fs::create_dir_all(&staged).unwrap();
    project_json(&staged, &project);
    for i in 1..=4 {
        topic(&staged, i, "");
    }
    std::fs::write(staged.join("MEMORY.md"), "# Notes\n- [Topic 4](t4.md) — hook 4\n").unwrap();
    let dir = tmp.path().join("data/auto").join(key(&project));
    std::fs::create_dir_all(dir.parent().unwrap()).unwrap();
    std::fs::rename(&staged, &dir).unwrap();
    wait_for("4 entries in MEMORY.md", || index(&dir).matches("](t").count() == 4);
    assert!(index(&dir).starts_with("# Notes\n- [Topic 4](t4.md) — hook 4\n"), "{}", index(&dir));
    wait_for("4 pages", || (1..=4).all(|i| page(&engine.socket, &format!("t{i}.md")).contains(&format!("albatross{i}"))));
    let found = tool(&engine.socket, "memory_query", serde_json::json!({
        "query": "albatross3", "workspace": "default", "project": "acme", "limit": 5,
    }));
    assert!(found.contains("auto/t3.md"), "search missed the page: {found}");

    topic(&dir, 1, " and then some");
    wait_for("the page updated", || page(&engine.socket, "t1.md").contains("and then some"));
    std::fs::remove_file(dir.join("t2.md")).unwrap();
    wait_for("the entry gone", || !index(&dir).contains("(t2.md)"));
    wait_for("the page gone", || !page(&engine.socket, "t2.md").contains("albatross2"));
    assert!(index(&dir).contains("(t1.md)") && index(&dir).starts_with("# Notes\n"));

    let log = Command::new("git").arg("-C").arg(tmp.path().join("data/wiki")).args(["log", "--format=%s"]).output().unwrap();
    let log = String::from_utf8_lossy(&log.stdout);
    assert!(log.contains("memory_write_page: auto/t3.md") && log.contains("memory_delete_page: auto/t2.md"), "not in the wiki's git: {log}");
}

#[test]
fn what_changed_while_the_engine_was_down_is_reconciled_at_start() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let dir = auto_folder(&tmp.path().join("data"), &project);
    topic(&dir, 1, "");
    topic(&dir, 2, "");
    std::fs::write(dir.join("MEMORY.md"), "- [Gone](gone.md) — deleted since\n").unwrap();
    let engine = start(tmp.path(), &["--keep-alive"]);
    wait_for("the index rebuilt", || {
        let text = index(&dir);
        text.contains("(t1.md)") && text.contains("(t2.md)") && !text.contains("gone.md")
    });
    wait_for("both pages", || page(&engine.socket, "t2.md").contains("albatross2"));
}
