import WebKit

/// The element picker's script (docs/adr/0018-element-picker.md). It runs
/// in its own content world: it shares the page's DOM but not its
/// JavaScript, so the page never sees it. The app asks, it answers:
/// `at(x, y)` while hovering, `describe(x, y)` on the click, both in CSS
/// pixels of the top viewport. Injected when picking starts and again after
/// each navigation; running it twice changes nothing.
enum PickerScript {
    @MainActor static var world: WKContentWorld { .world(name: "cadex-picker") }

    /// The call for one question; the script goes first when the document
    /// does not have it yet. The answer is JSON text ("null": nothing there).
    static func call(_ function: String, x: Double, y: Double, inject: Bool) -> String {
        let call = "JSON.stringify(window.__cadexPicker.\(function)(\(x), \(y)))"
        return inject ? source + "\n" + call : call
    }

    static let source = #"""
    if (!window.__cadexPicker) {
      window.__cadexPicker = (() => {
        // Children deeper than this become "…": the agent needs the shape,
        // not a whole subtree (plan 16).
        const MAX_DEPTH = 2;

        // The element under a point, entering open shadow roots and
        // same-origin frames, with its box in the top viewport.
        function hit(x, y) {
          let doc = document, ox = 0, oy = 0, el = null;
          const frames = [];
          for (let guard = 0; guard < 8; guard++) {
            el = doc.elementFromPoint(x - ox, y - oy);
            if (!el) return null;
            while (el.shadowRoot) {
              const inner = el.shadowRoot.elementFromPoint(x - ox, y - oy);
              if (!inner || inner === el) break;
              el = inner;
            }
            if (el.tagName !== 'IFRAME' && el.tagName !== 'FRAME') break;
            let inner = null;
            try { inner = el.contentDocument; } catch (e) {}
            if (!inner || !inner.documentElement) break;
            const r = el.getBoundingClientRect();
            ox += r.left + el.clientLeft;
            oy += r.top + el.clientTop;
            frames.push(el);
            doc = inner;
          }
          const r = el.getBoundingClientRect();
          return { el, frames, box: { x: r.left + ox, y: r.top + oy, w: r.width, h: r.height } };
        }

        function classes(el) { return Array.from(el.classList || []); }
        function esc(s) { return window.CSS && CSS.escape ? CSS.escape(s) : s; }

        function short(el) {
          const tag = el.tagName.toLowerCase();
          if (el.id) return tag + '#' + el.id;
          const cls = classes(el).slice(0, 2);
          return tag + (cls.length ? '.' + cls.join('.') : '');
        }

        function step(el) {
          const tag = el.tagName.toLowerCase();
          if (el.id) return '#' + esc(el.id);
          const test = el.getAttribute('data-testid');
          if (test) return tag + '[data-testid="' + test.replace(/"/g, '\\"') + '"]';
          let s = tag + classes(el).slice(0, 3).map((c) => '.' + esc(c)).join('');
          const parent = el.parentElement;
          if (parent) {
            const same = Array.from(parent.children).filter((c) => c.tagName === el.tagName);
            if (same.length > 1) s += ':nth-of-type(' + (same.indexOf(el) + 1) + ')';
          }
          return s;
        }

        function unique(root, sel) {
          try { return root.querySelectorAll(sel).length === 1; } catch (e) { return false; }
        }

        // Climbs until the path is unique in its document or shadow root;
        // a shadow root's host comes first, joined by ">>>".
        function selector(el) {
          const root = el.getRootNode();
          const parts = [];
          for (let node = el; node && node.nodeType === 1 && parts.length < 6; node = node.parentElement) {
            parts.unshift(step(node));
            if (unique(root, parts.join(' > '))) break;
          }
          const sel = parts.join(' > ');
          return root.host ? selector(root.host) + ' >>> ' + sel : sel;
        }

        function prune(node, depth) {
          for (const child of Array.from(node.childNodes)) {
            if (child.nodeType === 8) child.remove();
          }
          if (depth >= MAX_DEPTH && node.children.length) { node.replaceChildren('…'); return; }
          for (const child of Array.from(node.children)) {
            const tag = child.tagName.toLowerCase();
            if (tag === 'script' || tag === 'style') child.textContent = '';
            else if (tag === 'svg') child.replaceChildren();
            else prune(child, depth + 1);
            shorten(child);
          }
        }

        function shorten(el) {
          for (const a of Array.from(el.attributes || [])) {
            let v = a.value;
            if (v.startsWith('data:')) v = 'data:…';
            else if (v.length > 120) v = v.slice(0, 120) + '…';
            if (v !== a.value) el.setAttribute(a.name, v);
          }
        }

        function html(el) {
          const copy = el.cloneNode(true);
          if (copy.tagName && copy.tagName.toLowerCase() === 'svg') copy.replaceChildren();
          else prune(copy, 0);
          shorten(copy);
          return (copy.outerHTML || '').slice(0, 6000);
        }

        function label(h) {
          return short(h.el) + '  ' + Math.round(h.box.w) + '×' + Math.round(h.box.h);
        }

        return {
          at(x, y) {
            const h = hit(x, y);
            return h ? { box: h.box, label: label(h) } : null;
          },
          describe(x, y) {
            const h = hit(x, y);
            if (!h) return null;
            const frames = h.frames.map(selector);
            return {
              box: h.box,
              label: label(h),
              selector: frames.concat([selector(h.el)]).join(' >>> '),
              html: html(h.el),
              text: (h.el.innerText || h.el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 400),
              viewport: { w: window.innerWidth, h: window.innerHeight },
            };
          },
        };
      })();
    }
    """#
}
