//! Plan 40 A2 (docs/plans/40-memory-panel.md): write the fake memory folder
//! the panel tests use (tests/panel/seed.rs) into an empty folder, for the
//! side-by-side screenshots and the app's tests. Then, for upstream's panel
//! over it: cargo run --example web_reference -- <folder>
//!
//! cargo run --example panel_seed -- <empty folder>

#[path = "../tests/panel/seed.rs"]
mod seed;

use anyhow::{Context, Result, ensure};

#[tokio::main]
async fn main() -> Result<()> {
    let dir = std::env::args().nth(1).context("usage: panel_seed <empty folder>")?;
    let dir = std::path::Path::new(&dir);
    // Never over a real memory: seeding adds to whatever store is there.
    ensure!(
        !dir.exists() || std::fs::read_dir(dir)?.next().is_none(),
        "{} is not empty",
        dir.display()
    );
    seed::seed(dir).await?;
    eprintln!("seeded {}", dir.display());
    Ok(())
}
