//! Plan 40 A (docs/plans/40-memory-panel.md): upstream's web panel, as
//! `ai-memory serve` mounts it, over a COPY of a memory folder, on 127.0.0.1
//! only: the reference screenshots for the native screens. Every request is
//! the local owner (root), as a single-user Cadex is; no login.
//!
//! cargo run --example web_reference -- <copy of the memory folder> [port]

use std::net::SocketAddr;

use ai_memory_core::AuthLevel;
use ai_memory_store::Store;
use ai_memory_web::{Recall, WebMountSpec, split_web_routers};
use ai_memory_wiki::Wiki;
use anyhow::{Context, Result};

#[tokio::main]
async fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let dir = args.next().context("usage: web_reference <memory folder copy> [port]")?;
    let port: u16 = args.next().map(|p| p.parse()).transpose()?.unwrap_or(49_390);
    let store = Store::open(std::path::Path::new(&dir)).context("opening the store")?;
    let wiki = Wiki::new(std::path::Path::new(&dir), store.writer.clone())?;
    let web = split_web_routers(
        true,
        store.reader.clone(),
        wiki,
        WebMountSpec {
            enable_api: true,
            web_ui_dir: None,
            cors_origins: &[],
            web_slug: "/web",
            base_href: "/web/",
            base_path: "",
            trusted_proxy_identity: false,
            recall: Recall::default(),
            runtime: None,
            health: None,
        },
    )?;
    let app = web
        .protected
        .layer(axum::middleware::from_fn(|mut req: axum::extract::Request, next: axum::middleware::Next| async move {
            req.extensions_mut().insert(AuthLevel::Root);
            next.run(req).await
        }))
        .merge(web.public);
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    eprintln!("http://{addr}/web/");
    axum::serve(listener, app).await?;
    Ok(())
}
