//! **Copied from upstream** (ai-memory, commit
//! fa0ec25dbe987b7574a7487ecf92f0873040c2f2, 2026-11-16),
//! crates/ai-memory-hooks/src/router.rs, private there:
//! - `render_handoff_markdown_with_budget` → [`render`]
//! - `escape_untrusted_history` and `escape_untrusted_history_tail` →
//!   [`escape_tail`]
//! - `CLAUDE_HANDOFF_CHARS` and `CLAUDE_ADDITIONAL_CONTEXT_CHARS`
//!
//! The Memory page's briefing (briefing.rs) asks upstream's `/handoff` with
//! `claim=0`, which puts a one-line notice where a claimed handoff's text
//! goes; this renders the text the claiming SessionStart would get, so the
//! page shows it without consuming the baton. Same layout, budget and
//! escaping; update with upstream.

use ai_memory_core::Handoff;
use ai_memory_core::profile::{UNTRUSTED_HISTORY_END, UNTRUSTED_HISTORY_START};
use ai_memory_hooks::BACKFILL_MARKER_PREFIX;

/// A Claude Code SessionStart's handoff budget (`CLAUDE_HANDOFF_CHARS`).
pub(crate) const CLAUDE_HANDOFF_CHARS: usize = 4_800;
/// Claude Code's inline hook ceiling (`CLAUDE_ADDITIONAL_CONTEXT_CHARS`).
pub(crate) const CLAUDE_ADDITIONAL_CONTEXT_CHARS: usize = 9_800;

fn escape_untrusted_history(text: &str) -> String {
    text.replace(UNTRUSTED_HISTORY_START, "&lt;!-- ai-memory:untrusted-history:start --&gt;")
        .replace(UNTRUSTED_HISTORY_END, "&lt;!-- ai-memory:untrusted-history:end --&gt;")
}

fn escape_tail(buf: &mut String, start: usize) {
    let escaped = escape_untrusted_history(&buf[start..]).replace(BACKFILL_MARKER_PREFIX, "&lt;!-- ai-memory:backfill ");
    buf.truncate(start);
    buf.push_str(&escaped);
}

/// The handoff as a claiming SessionStart renders it.
pub(crate) fn render(h: &Handoff, budget: Option<usize>) -> String {
    let mut buf = String::with_capacity(512);
    buf.push_str("> 📥 **ai-memory: pending handoff from previous session**\n");
    buf.push_str(&format!(
        "> from `{from}` · created {ts}\n",
        from = h.origin.from_agent.as_str(),
        ts = h.lifecycle.created_at,
    ));
    if let Some(session_id) = h.origin.from_session_id {
        buf.push_str(&format!(
            "> session record: `sessions/{session_id}.md` — read it with \
             `memory_read_page` for the full session; when LLM consolidation is \
             enabled it is rewritten there shortly after the session ends.\n",
        ));
    }
    buf.push_str("> **Security boundary:** ");
    buf.push_str(ai_memory_core::UNTRUSTED_MEMORY_NOTICE);
    buf.push_str("\n\n");
    buf.push_str(UNTRUSTED_HISTORY_START);
    buf.push('\n');
    let history_start = buf.len();

    if !h.content.open_questions.is_empty() {
        buf.push_str("\n**Open questions**\n");
        for q in &h.content.open_questions {
            buf.push_str(&format!("- {q}\n"));
        }
    }
    if !h.content.next_steps.is_empty() {
        buf.push_str("\n**Next steps**\n");
        for s in &h.content.next_steps {
            buf.push_str(&format!("- {s}\n"));
        }
    }
    if !h.content.files_touched.is_empty() {
        buf.push_str("\n**Files touched**\n");
        for f in &h.content.files_touched {
            buf.push_str(&format!("- `{f}`\n"));
        }
    }

    buf.push_str("\n**Summary**\n");
    buf.push_str(h.content.summary.trim());
    buf.push('\n');
    escape_tail(&mut buf, history_start);
    if let Some(budget) = budget {
        let footer_room = UNTRUSTED_HISTORY_END.chars().count() + 520;
        let ceiling = budget.saturating_sub(footer_room).max(history_start);
        if buf.chars().count() > ceiling {
            let cut = buf.char_indices().nth(ceiling).map_or(buf.len(), |(at, _)| at);
            buf.truncate(cut);
            buf.push_str("\n[handoff detail omitted to fit this harness's startup limit]\n");
        }
    }
    buf.push('\n');
    buf.push_str(UNTRUSTED_HISTORY_END);
    buf.push('\n');

    buf.push_str(
        "\n---\n\
         _**To the receiving agent:** this content IS the pending \
         handoff — already consumed by the SessionStart hook. A \
         subsequent `memory_handoff_accept` call returns no handoff \
         (single-use). When the user asks \
         \"where did we leave off?\" or \"any pending handoff?\", \
         answer from THIS content; do NOT re-call the tool. Call \
         `memory_query` / `memory_recent` only for additional \
         context beyond what's listed here._\n",
    );
    buf
}
