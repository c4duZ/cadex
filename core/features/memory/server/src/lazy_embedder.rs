//! The local embedder, loaded on first use and dropped after idling.
//!
//! Upstream `LocalEmbedder::load` reads the ~87 MB model at startup and keeps
//! it for the life of the process. Cadex wants the engine light while parked
//! (plan 22, phase D): the model is loaded only to index or search and is
//! released after `idle` without use. While the model files are absent (first
//! run) the embedder answers with an error, which the wiki and `memory_query`
//! already treat as "FTS only", and fetches the files once in the background
//! (model_fetch.rs: a dropped download resumes; a failed one is tried again
//! after `RETRY_AFTER`, not on every search, so an offline Mac does not
//! knock on every query).
//! Each load and unload is told to [`ModelEvents`]: after an unload the
//! engine restarts itself to give the allocator's memory back (restart.rs).

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant};

use ai_memory_llm::{Embedder, LOCAL_DIM, LOCAL_MODEL, LlmError, LlmResult, LocalEmbedder};
use tokio::sync::Mutex;

use crate::model_fetch;
use crate::restart::ModelEvents;

/// After a failed fetch (offline, a cut connection), the next try waits this
/// long; a new engine (the next session's) tries at once.
const RETRY_AFTER: Duration = Duration::from_secs(600);

/// Shared state between the embedder handle and its idle reaper task.
struct Slot {
    model: Mutex<Option<Arc<LocalEmbedder>>>,
    /// Milliseconds since `epoch` of the last embed call.
    last_use_ms: AtomicU64,
    epoch: Instant,
    reaper_running: AtomicBool,
    events: Arc<ModelEvents>,
}

/// An [`Embedder`] over the local all-MiniLM model with lazy load and idle unload.
pub struct LazyLocalEmbedder {
    models_dir: PathBuf,
    idle: Duration,
    slot: Arc<Slot>,
    fetching: Arc<AtomicBool>,
    /// When the last fetch failed, if one did.
    failed_at: Arc<std::sync::Mutex<Option<Instant>>>,
}

impl LazyLocalEmbedder {
    /// A handle that loads from `<models_dir>/all-MiniLM-L6-v2/` on demand.
    pub fn new(models_dir: PathBuf, idle: Duration, events: Arc<ModelEvents>) -> Self {
        Self {
            models_dir,
            idle,
            slot: Arc::new(Slot {
                model: Mutex::new(None),
                last_use_ms: AtomicU64::new(0),
                epoch: Instant::now(),
                reaper_running: AtomicBool::new(false),
                events,
            }),
            fetching: Arc::new(AtomicBool::new(false)),
            failed_at: Arc::new(std::sync::Mutex::new(None)),
        }
    }

    fn touch(&self) {
        let now = self.slot.epoch.elapsed().as_millis() as u64;
        self.slot.last_use_ms.store(now, Ordering::Relaxed);
    }

    fn start_fetch(&self) {
        let recent_failure = self.failed_at.lock().ok().and_then(|at| *at).is_some_and(|at| at.elapsed() < RETRY_AFTER);
        if recent_failure || self.fetching.swap(true, Ordering::SeqCst) {
            return;
        }
        let dir = ai_memory_llm::local::model_dir(&self.models_dir);
        let fetching = self.fetching.clone();
        let failed_at = self.failed_at.clone();
        let events = self.slot.events.clone();
        events.fetching.store(true, Ordering::SeqCst);
        tokio::spawn(async move {
            tracing::info!(dir = %dir.display(), "fetching the local embedding model (~87 MB, once)");
            let files = ai_memory_llm::local::MODEL_FILES;
            match model_fetch::fetch(&dir, model_fetch::MODEL_BASE_URL, &files).await {
                Ok(()) => tracing::info!("local embedding model fetched; hybrid search is on"),
                Err(error) => {
                    tracing::warn!(%error, "local embedding model fetch failed; FTS only, trying again later");
                    if let Ok(mut at) = failed_at.lock() {
                        *at = Some(Instant::now());
                    }
                    fetching.store(false, Ordering::SeqCst);
                }
            }
            events.fetching.store(false, Ordering::SeqCst);
        });
    }

    async fn model(&self) -> LlmResult<Arc<LocalEmbedder>> {
        let mut guard = self.slot.model.lock().await;
        if let Some(model) = guard.as_ref() {
            return Ok(model.clone());
        }
        if !ai_memory_llm::model_present(&self.models_dir) {
            self.start_fetch();
            return Err(LlmError::NotConfigured(
                "local embedding model not downloaded yet".into(),
            ));
        }
        let dir = self.models_dir.clone();
        let started = Instant::now();
        let model = tokio::task::spawn_blocking(move || LocalEmbedder::load(&dir))
            .await
            .map_err(|e| LlmError::UnexpectedShape(format!("model load task: {e}")))??;
        tracing::info!(ms = started.elapsed().as_millis() as u64, "local embedding model loaded");
        let model = Arc::new(model);
        *guard = Some(model.clone());
        self.slot.events.loaded.store(true, Ordering::SeqCst);
        self.spawn_reaper();
        Ok(model)
    }

    /// One task per loaded period: sleeps until the model has idled for
    /// `idle`, drops it and exits, so a parked engine runs no timer.
    fn spawn_reaper(&self) {
        if self.slot.reaper_running.swap(true, Ordering::SeqCst) {
            return;
        }
        let slot = self.slot.clone();
        let idle = self.idle;
        tokio::spawn(async move {
            loop {
                let now = slot.epoch.elapsed().as_millis() as u64;
                let last = slot.last_use_ms.load(Ordering::Relaxed);
                let idle_ms = idle.as_millis() as u64;
                let since = now.saturating_sub(last);
                if since >= idle_ms {
                    let mut guard = slot.model.lock().await;
                    // Re-check under the lock: an embed may have just started.
                    let now = slot.epoch.elapsed().as_millis() as u64;
                    if now.saturating_sub(slot.last_use_ms.load(Ordering::Relaxed)) >= idle_ms {
                        *guard = None;
                        slot.reaper_running.store(false, Ordering::SeqCst);
                        slot.events.loaded.store(false, Ordering::SeqCst);
                        slot.events.unloaded.notify_one();
                        tracing::info!("local embedding model unloaded after idling");
                        return;
                    }
                    continue;
                }
                tokio::time::sleep(Duration::from_millis(idle_ms - since)).await;
            }
        });
    }
}

#[async_trait::async_trait]
impl Embedder for LazyLocalEmbedder {
    fn provider(&self) -> &'static str {
        "local"
    }

    fn model(&self) -> &str {
        LOCAL_MODEL
    }

    fn dim(&self) -> u32 {
        LOCAL_DIM
    }

    async fn embed(&self, text: &str) -> LlmResult<Vec<f32>> {
        self.touch();
        let model = self.model().await?;
        let out = model.embed(text).await;
        self.touch();
        out
    }
}
