//! The recall trace of `extra/search` (search.rs): one hit's stream table
//! and the per-stream times, formatted as upstream's search screen prints
//! them (ai-memory-web's routes/search.rs at 411d90d: `hit_trace`,
//! `timing_rows`, `fmt_rank`, `fmt_f64`, `fmt_rrf`, **copied**), so the
//! native "Explicar classificação" shows the same numbers as its page
//! (tests/panel/screen_search.rs holds them equal).

use ai_memory_store::{SearchExplain, StreamTimings};
use serde::Serialize;

/// One stream's line: its rank, raw score and RRF share, as text.
#[derive(Serialize)]
pub(super) struct StreamRow {
    stream: &'static str,
    rank: String,
    raw: String,
    rrf: String,
}

/// Upstream's `HitTrace`, field for field.
#[derive(Serialize)]
pub(super) struct HitTrace {
    position: usize,
    rank: String,
    fused: String,
    authority: String,
    intent_boost: Option<String>,
    rerank_score: Option<String>,
    streams: Vec<StreamRow>,
    matched_entities: String,
    graph_via: Option<String>,
}

#[derive(Serialize)]
pub(super) struct TimingRow {
    stream: &'static str,
    ms: String,
}

fn dash() -> String {
    "—".to_owned()
}

fn fmt_rank(rank: Option<usize>) -> String {
    rank.map_or_else(dash, |r| r.to_string())
}

fn fmt_f64(value: Option<f64>) -> String {
    value.map_or_else(dash, |v| format!("{v:.4}"))
}

fn fmt_rrf(value: f64) -> String {
    if value == 0.0 { dash() } else { format!("{value:.5}") }
}

fn row(stream: &'static str, rank: Option<usize>, raw: String, rrf: f64) -> StreamRow {
    StreamRow { stream, rank: fmt_rank(rank), raw, rrf: fmt_rrf(rrf) }
}

/// One hit's trace, in the stream order upstream's table uses.
pub(super) fn hit_trace(position: usize, rank: f64, d: &SearchExplain) -> HitTrace {
    let mut streams = vec![
        row("fts", d.fts_rank, fmt_f64(d.fts_score), d.rrf.fts),
        row("entity", d.entity_rank, fmt_f64(d.entity_weight), d.rrf.entity),
        row("vector", d.vector_rank, fmt_f64(d.cosine.map(f64::from)), d.rrf.vector),
    ];
    if d.abstract_rank.is_some() || d.rrf.abstract_vector != 0.0 {
        streams.push(row("abstract", d.abstract_rank, fmt_f64(d.abstract_cosine.map(f64::from)), d.rrf.abstract_vector));
    }
    streams.push(row("graph", d.graph_rank, dash(), d.rrf.graph));
    if d.observation_rank.is_some() || d.rrf.observation != 0.0 {
        streams.push(row("observation", d.observation_rank, dash(), d.rrf.observation));
    }
    HitTrace {
        position,
        rank: format!("{rank:.5}"),
        fused: format!("{:.5}", d.fused),
        authority: fmt_f64(d.authority),
        intent_boost: d.intent_boost.map(|v| format!("{v:.3}")),
        rerank_score: d.rerank_score.map(|v| format!("{v:.3}")),
        streams,
        matched_entities: d.matched_entities.join(", "),
        graph_via: d.graph_via.as_ref().map(|via| match &via.edge {
            Some(edge) => format!("{} ({}, {edge})", via.seed_path, via.direction),
            None => format!("{} ({})", via.seed_path, via.direction),
        }),
    }
}

/// The streams that ran and how long each took, in milliseconds.
pub(super) fn timing_rows(t: &StreamTimings) -> Vec<TimingRow> {
    [
        ("fts", t.fts_ms),
        ("entity", t.entity_ms),
        ("vector", t.vector_ms),
        ("graph", t.graph_ms),
        ("observation", t.observation_ms),
        ("rerank", t.rerank_ms),
    ]
    .into_iter()
    .filter_map(|(stream, ms)| ms.map(|ms| TimingRow { stream, ms: format!("{ms:.2}") }))
    .collect()
}
