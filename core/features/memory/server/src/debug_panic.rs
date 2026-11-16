//! A panic on request, for the test that no hook event is lost when the
//! engine dies (plan 22, phase C validation: "com um pânico forçado, a fila
//! guarda e esvazia quando ele volta"). Compiled only in debug builds (the
//! tests' and `make run`'s), and only with `CADEX_MEMORY_TEST_PANIC=1` in
//! the engine's environment: the release binary has neither the route nor
//! the variable's check.
//!
//! The release profile has `panic = "abort"` (Cargo.toml): a panic anywhere
//! ends the process. A debug build unwinds, and tokio would catch a panic in
//! the request's task and keep serving, so the hook installed here aborts
//! after the usual message, making the debug engine die the way the release
//! one does.

use axum::Router;
use axum::routing::post;

pub(crate) const ENV: &str = "CADEX_MEMORY_TEST_PANIC";

pub(crate) fn enabled() -> bool {
    std::env::var(ENV).is_ok_and(|v| v == "1")
}

/// Every panic aborts the process, as in release.
pub(crate) fn abort_on_panic() {
    let default = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        default(info);
        std::process::abort();
    }));
}

/// `POST /debug/panic` (behind the session token, like every route).
pub(crate) fn route(router: Router) -> Router {
    router.route("/debug/panic", post(forced))
}

async fn forced() -> &'static str {
    panic!("forced by {ENV} (test)")
}
