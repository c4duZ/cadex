//! Fetching the embedding model so that a dropped connection resumes where
//! it stopped (plan 22 phase D: "com retomada se cair e conferência do
//! arquivo"). Upstream's `ai_memory_llm::fetch_model` reads each file whole
//! into memory and starts over after a failure; this keeps upstream's file
//! list and pinned SHA-256s (`ai_memory_llm::local::MODEL_FILES`) and its
//! address (`MODEL_BASE_URL` in local.rs at fa0ec25, private there, copied
//! here), and streams each file into `<name>.part`, asking with `Range` for
//! the rest when a part is there. A file is renamed into place only when its
//! SHA-256 matches the pin; a mismatch deletes the part. `LocalEmbedder::load`
//! checks the pins again.

use std::io::Write;
use std::path::Path;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use sha2::{Digest, Sha256};

pub(crate) const MODEL_BASE_URL: &str = "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main";

fn sha256_hex(path: &Path) -> Result<String> {
    let mut hasher = Sha256::new();
    let mut file = std::fs::File::open(path)?;
    std::io::copy(&mut file, &mut hasher)?;
    Ok(hasher.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

/// Every file of `files` into `dir`, verified, resuming parts left by an
/// earlier try.
pub(crate) async fn fetch(dir: &Path, base: &str, files: &[(&str, &str)]) -> Result<()> {
    std::fs::create_dir_all(dir)?;
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(30))
        .read_timeout(Duration::from_secs(60))
        .build()?;
    for (name, pin) in files {
        let dest = dir.join(name);
        if dest.exists() {
            if sha256_hex(&dest)? == *pin {
                continue;
            }
            std::fs::remove_file(&dest)?;
        }
        let part = dir.join(format!("{name}.part"));
        fetch_file(&client, &format!("{base}/{name}"), &part).await?;
        if sha256_hex(&part)? != *pin {
            let _ = std::fs::remove_file(&part);
            bail!("{name}: the download does not match its pinned sha256; deleted");
        }
        std::fs::rename(&part, &dest)?;
    }
    Ok(())
}

async fn fetch_file(client: &reqwest::Client, url: &str, part: &Path) -> Result<()> {
    let have = std::fs::metadata(part).map(|m| m.len()).unwrap_or(0);
    let mut request = client.get(url);
    if have > 0 {
        request = request.header(reqwest::header::RANGE, format!("bytes={have}-"));
    }
    let mut response = request.send().await.with_context(|| format!("GET {url}"))?;
    let status = response.status();
    if status == reqwest::StatusCode::RANGE_NOT_SATISFIABLE {
        // The part is already whole; the pin decides.
        return Ok(());
    }
    let response_ok = status.is_success();
    if !response_ok {
        bail!("GET {url}: {status}");
    }
    let resumed = status == reqwest::StatusCode::PARTIAL_CONTENT;
    let mut file = std::fs::OpenOptions::new().create(true).append(resumed).write(true).truncate(!resumed).open(part)?;
    while let Some(chunk) = response.chunk().await.with_context(|| format!("reading {url}"))? {
        file.write_all(&chunk)?;
    }
    file.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    /// A one-file HTTP server that honours `Range` and, on the first
    /// request, sends only `cut` bytes of the body before closing.
    async fn server(body: Vec<u8>, cut: Option<usize>) -> (String, Arc<AtomicUsize>, Arc<std::sync::Mutex<Vec<String>>>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let served = Arc::new(AtomicUsize::new(0));
        let ranges = Arc::new(std::sync::Mutex::new(Vec::new()));
        let (count, seen) = (served.clone(), ranges.clone());
        tokio::spawn(async move {
            loop {
                let (mut stream, _) = listener.accept().await.unwrap();
                let mut buf = vec![0u8; 4096];
                let n = stream.read(&mut buf).await.unwrap();
                let head = String::from_utf8_lossy(&buf[..n]).to_string();
                let from = head
                    .lines()
                    .find_map(|l| l.to_ascii_lowercase().strip_prefix("range: bytes=").map(|r| r.trim_end_matches('-').parse::<usize>().unwrap()))
                    .unwrap_or(0);
                seen.lock().unwrap().push(format!("{from}"));
                let first = count.fetch_add(1, Ordering::SeqCst) == 0;
                let rest = &body[from..];
                let status = if from > 0 { "206 Partial Content" } else { "200 OK" };
                let reply = format!("HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", rest.len());
                stream.write_all(reply.as_bytes()).await.unwrap();
                let send = match cut { Some(c) if first => &rest[..c], _ => rest };
                let _ = stream.write_all(send).await;
                let _ = stream.shutdown().await;
            }
        });
        (base, served, ranges)
    }

    fn pin(bytes: &[u8]) -> String {
        Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
    }

    #[tokio::test]
    async fn a_dropped_download_resumes_where_it_stopped() {
        let body: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
        let pinned = pin(&body);
        let (base, _served, ranges) = server(body.clone(), Some(70_000)).await;
        let dir = tempfile::tempdir().unwrap();
        let files = [("model.bin", pinned.as_str())];
        assert!(fetch(dir.path(), &base, &files).await.is_err(), "the cut connection fails the first try");
        assert_eq!(std::fs::metadata(dir.path().join("model.bin.part")).unwrap().len(), 70_000);
        fetch(dir.path(), &base, &files).await.unwrap();
        assert_eq!(std::fs::read(dir.path().join("model.bin")).unwrap(), body);
        assert_eq!(*ranges.lock().unwrap(), vec!["0".to_string(), "70000".to_string()]);
        assert!(!dir.path().join("model.bin.part").exists());
    }

    #[tokio::test]
    async fn a_corrupt_download_or_file_is_never_kept() {
        let body = b"the real model".to_vec();
        let (base, served, _) = server(b"tampered bytes".to_vec(), None).await;
        let dir = tempfile::tempdir().unwrap();
        let pinned = pin(&body);
        let files = [("model.bin", pinned.as_str())];
        assert!(fetch(dir.path(), &base, &files).await.is_err());
        assert!(!dir.path().join("model.bin").exists() && !dir.path().join("model.bin.part").exists());
        // A good file stays without a request; a broken one is fetched again.
        std::fs::write(dir.path().join("model.bin"), &body).unwrap();
        let before = served.load(Ordering::SeqCst);
        fetch(dir.path(), &base, &files).await.unwrap();
        assert_eq!(served.load(Ordering::SeqCst), before);
    }

    /// The real model from its real address, cut after 2 s and resumed
    /// (network; `cargo test -- --ignored real_model`, 2026-11-16).
    #[tokio::test]
    #[ignore]
    async fn real_model_resumes_after_a_cut() {
        let dir = tempfile::tempdir().unwrap();
        let files = ai_memory_llm::local::MODEL_FILES;
        let cut = tokio::time::timeout(Duration::from_secs(2), fetch(dir.path(), MODEL_BASE_URL, &files)).await;
        assert!(cut.is_err(), "the 87 MB took under 2 s; nothing to resume");
        let parts: Vec<_> = std::fs::read_dir(dir.path()).unwrap().map(|e| e.unwrap().file_name()).collect();
        eprintln!("after the cut: {parts:?}");
        let started = std::time::Instant::now();
        fetch(dir.path(), MODEL_BASE_URL, &files).await.unwrap();
        eprintln!("resumed and verified in {:?}", started.elapsed());
        for (name, pin) in files {
            assert_eq!(sha256_hex(&dir.path().join(name)).unwrap(), pin);
        }
    }

    #[tokio::test]
    async fn offline_fails_fast_and_keeps_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let started = std::time::Instant::now();
        let files = [("model.bin", "00")];
        assert!(fetch(dir.path(), "http://127.0.0.1:9", &files).await.is_err());
        assert!(started.elapsed() < Duration::from_secs(5));
        assert!(!dir.path().join("model.bin").exists());
    }
}
