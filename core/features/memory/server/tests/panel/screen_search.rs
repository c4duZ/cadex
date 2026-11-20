//! Plan 40 E: the engine's `extra/search` against upstream's search screen
//! (templates/search.html at the pinned commit) over the same folder: the
//! hits in order, their titles, snippets (the same `<mark>` HTML), project
//! and path, the count line, the scope options and, with "Explain ranking",
//! each hit's trace line and stream table. The times differ run to run;
//! only which streams ran is compared.

#![allow(dead_code)]

use serde_json::Value;

use super::panel::{get_ok, html, search_pairs};
use super::screens::Ours;

type App = axum::Router;

fn texts(v: &Value, key: &str) -> Vec<String> {
    v[key].as_array().unwrap().iter().map(|h| h.as_str().map(str::to_owned).unwrap_or_default()).collect()
}

/// The raw HTML of each hit's snippet `<div>`, as the template prints it.
fn snippet(chunk: &str) -> String {
    let start = "<div class=\"text-sm text-muted mb-1\">";
    let at = chunk.find(start).expect("a snippet") + start.len();
    let rest = &chunk[at..];
    rest[..rest.find("</div>").unwrap()].to_owned()
}

fn trace_line(t: &Value) -> String {
    let mut line = format!("#{} · rank {} · fused {} · authority {}", t["position"], s(&t["rank"]), s(&t["fused"]), s(&t["authority"]));
    if let Some(boost) = t["intent_boost"].as_str() {
        line.push_str(&format!(" · intent boost {boost}"));
    }
    if let Some(score) = t["rerank_score"].as_str() {
        line.push_str(&format!(" · rerank {score}"));
    }
    line
}

fn s(v: &Value) -> String {
    v.as_str().unwrap_or_default().to_owned()
}

pub async fn search(app: &App, ours: &Ours<'_>) {
    for (suffix, theirs) in search_pairs() {
        let page = get_ok(app, &theirs).await;
        let answer = ours.get(&suffix);
        let hits = answer["hits"].as_array().unwrap();
        let chunks = html::chunks(&page, "<li class=\"py-4\" data-hit-path=");
        let paths: Vec<String> = chunks.iter().map(|c| html::attr_values(&format!(" {c}"), "data-hit-path")[0].clone()).collect();
        let ours_paths: Vec<String> = hits.iter().map(|h| s(&h["path"])).collect();
        assert_eq!(ours_paths, paths, "{suffix}: the same hits in the same order");
        for (hit, chunk) in hits.iter().zip(&chunks) {
            assert_eq!(s(&hit["title"]), html::inner_texts(chunk, "a")[0], "{suffix}");
            assert_eq!(s(&hit["snippet"]).trim(), snippet(chunk).trim(), "{suffix}: the snippet's HTML");
            let place = format!("{}/{} · {}", s(&hit["workspace"]), s(&hit["project"]), s(&hit["path"]));
            assert!(html::text(chunk).contains(&place), "{suffix}: {place}");
            let traced = chunk.contains("data-trace");
            assert_eq!(hit["trace"].is_object(), traced, "{suffix}: a trace where upstream draws one");
            if traced {
                let trace = &hit["trace"];
                assert!(html::text(chunk).contains(&trace_line(trace)), "{suffix}: {} not in {}", trace_line(trace), html::text(chunk));
                let rows: Vec<String> = trace["streams"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|r| format!("{} {} {} {}", s(&r["stream"]), s(&r["rank"]), s(&r["raw"]), s(&r["rrf"])))
                    .collect();
                assert!(rows.iter().all(|r| html::text(chunk).contains(r)), "{suffix}: {rows:?}");
                assert_eq!(rows.len() + 1, html::count(chunk, "<tr>"), "{suffix}: one row per stream");
            }
        }
        let text = html::text(&page);
        let query = s(&answer["query"]);
        if !query.is_empty() && !hits.is_empty() {
            let count = if answer["truncated"] == true {
                format!("first {} results", answer["max_results"])
            } else {
                format!("{} result", hits.len())
            };
            assert!(text.contains(&count), "{suffix}: {count}");
        }
        if !query.is_empty() && hits.is_empty() {
            assert!(text.contains(&format!("No results for {query}")), "{suffix}");
            assert_eq!(answer["filtered"] == true, text.contains("with these filters"), "{suffix}");
        }
        if !s(&answer["unknown_kind"]).is_empty() {
            assert!(text.contains(&s(&answer["unknown_kind"])), "{suffix}");
        }
        if answer["explain"] == true && !query.is_empty() && !s(&answer["project"]).is_empty() {
            assert!(text.contains(&s(&answer["streams_active"])), "{suffix}: {}", answer["streams_active"]);
        }
        let options: Vec<String> = html::attr_values(&page[page.find("id=\"search-scope\"").unwrap()..page.find("id=\"search-kind\"").unwrap()], "value")
            .into_iter()
            .filter(|v| !v.is_empty())
            .collect();
        let ours_options: Vec<String> = answer["scopes"]
            .as_array()
            .unwrap()
            .iter()
            .flat_map(|g| texts(g, "projects").into_iter().map(move |p| format!("{}/{p}", s(&g["workspace"]))))
            .collect();
        assert_eq!(ours_options, options, "{suffix}: the scope selector");
    }
}
