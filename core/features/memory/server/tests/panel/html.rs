//! Plan 40 A2: pulling numbers and lists out of upstream's panel HTML, so a
//! native screen's JSON (phase B on) can be compared with what upstream's
//! own screen shows for the same seed. Plain string scanning, no HTML parser
//! crate: upstream's templates are ours to read at the pinned commit, and the
//! markers each helper takes are copied from them (templates/*.html).

#![allow(dead_code)]

/// The text of `html` with tags removed, entities for &, <, >, " and '
/// decoded and runs of whitespace folded to one space.
pub fn text(html: &str) -> String {
    let mut out = String::with_capacity(html.len());
    let mut in_tag = false;
    for c in html.chars() {
        match c {
            '<' => in_tag = true,
            '>' if in_tag => {
                in_tag = false;
                out.push(' ');
            }
            _ if !in_tag => out.push(c),
            _ => {}
        }
    }
    let decoded = out
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&#x27;", "'")
        .replace("&amp;", "&");
    decoded.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The pieces of `html` that start at each `start` marker and run to the next
/// one (or the end): one chunk per card, row or list item.
pub fn chunks<'a>(html: &'a str, start: &str) -> Vec<&'a str> {
    let starts: Vec<usize> = html.match_indices(start).map(|(i, _)| i).collect();
    starts
        .iter()
        .enumerate()
        .map(|(n, &from)| &html[from..starts.get(n + 1).copied().unwrap_or(html.len())])
        .collect()
}

/// The text inside every `<tag ...>…</tag>` of `html`, in order (no nesting
/// of the same tag, which upstream's `<strong>` and `<h3>` never do).
pub fn inner_texts(html: &str, tag: &str) -> Vec<String> {
    let open = format!("<{tag}");
    let close = format!("</{tag}>");
    let mut out = Vec::new();
    let mut rest = html;
    while let Some(at) = rest.find(&open) {
        let after = &rest[at + open.len()..];
        // `<strong` must not match `<strongest`: the next byte ends the name.
        if !after.starts_with(['>', ' ', '\n', '\t']) {
            rest = after;
            continue;
        }
        let Some(gt) = after.find('>') else { break };
        let body = &after[gt + 1..];
        let Some(end) = body.find(&close) else { break };
        out.push(text(&body[..end]));
        rest = &body[end + close.len()..];
    }
    out
}

/// The leading integer of each `<tag>` text (`"5 pages"` gives 5), or None
/// where the text does not start with a number (`"—"`).
pub fn numbers(html: &str, tag: &str) -> Vec<Option<u64>> {
    inner_texts(html, tag).iter().map(|t| leading_number(t)).collect()
}

/// The integer a text starts with, ignoring thousands separators (`1,234`).
pub fn leading_number(text: &str) -> Option<u64> {
    let digits: String = text
        .trim()
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == ',')
        .filter(char::is_ascii_digit)
        .collect();
    digits.parse().ok()
}

/// Every value of `name="…"` in `html`, in order (data-open, href, ...).
pub fn attr_values(html: &str, name: &str) -> Vec<String> {
    let needle = format!(" {name}=\"");
    html.match_indices(&needle)
        .filter_map(|(i, _)| {
            let value = &html[i + needle.len()..];
            value.find('"').map(|end| text(&value[..end]))
        })
        .collect()
}

/// The first value of `name="…"`, parsed as a number.
pub fn attr_number(html: &str, name: &str) -> Option<u64> {
    attr_values(html, name).first().and_then(|v| v.parse().ok())
}

/// How many times `needle` appears in `html`.
pub fn count(html: &str, needle: &str) -> usize {
    html.matches(needle).count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_card_numbers_and_attributes() {
        let html = r#"<a class="metric-card"><span>Projects</span><strong>4</strong></a>
<a class="metric-card"><strong>1,234 <small>pages</small></strong></a>
<article class="project-card" data-open="1"><h3><a href="x">cadex</a></h3></article>
<article class="project-card" data-open="0"><h3>a &amp; b</h3></article>"#;
        assert_eq!(numbers(html, "strong"), vec![Some(4), Some(1234)]);
        let cards = chunks(html, "<article class=\"project-card\"");
        assert_eq!(cards.len(), 2);
        assert_eq!(attr_number(cards[0], "data-open"), Some(1));
        assert_eq!(inner_texts(cards[1], "h3"), vec!["a & b"]);
        assert_eq!(leading_number("—"), None);
    }
}
