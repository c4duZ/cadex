import WebKit

/// What the agent reads of the page (docs/adr/0025-agent-drives-preview.md):
/// a script in the picker's own world (`cadex-picker`), which shares the
/// DOM but not the page's JavaScript. `snapshot()` lists the visible
/// elements with their role, name, value and state, giving the ones you can
/// use a reference (`@e1`) kept here until the next snapshot or navigation;
/// `box(ref)` scrolls one into view and gives its box in CSS pixels of the
/// viewport; `prepareFill(ref)` focuses a field and selects what it holds;
/// `exists(selector)` answers waits. Injected on demand, never a
/// `WKUserScript`; clicks and keys are the app's native events, not this.
enum BrowserScript {
    /// The call; the script goes first when the document does not have it.
    static func call(_ invocation: String, inject: Bool) -> String {
        let call = "JSON.stringify(window.__cadexBrowser.\(invocation))"
        return inject ? source + "\n" + call : call
    }

    /// A JavaScript string literal for `text`.
    static func literal(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    static let source = #"""
    if (!window.__cadexBrowser) {
      window.__cadexBrowser = (() => {
        let refs = new Map();
        const ACTIVE = new Set(['button', 'link', 'textbox', 'searchbox', 'checkbox', 'radio', 'combobox', 'listbox',
          'option', 'menuitem', 'menuitemcheckbox', 'tab', 'switch', 'slider', 'spinbutton', 'treeitem']);
        const CONTEXT = new Set(['heading', 'img', 'dialog', 'alert', 'navigation', 'main', 'form', 'list', 'listitem',
          'table', 'row', 'cell', 'columnheader', 'banner', 'contentinfo', 'region', 'status']);
        const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'HEAD', 'META', 'LINK']);

        function shown(el) {
          const s = getComputedStyle(el);
          if (s.display === 'none' || s.visibility === 'hidden' || s.visibility === 'collapse') return false;
          const r = el.getClientRects();
          return r.length > 0 && (r[0].width > 0 || r[0].height > 0);
        }

        function role(el) {
          const given = (el.getAttribute('role') || '').trim().split(/\s+/)[0];
          if (given) return given;
          const tag = el.tagName;
          const type = (el.getAttribute('type') || 'text').toLowerCase();
          if (tag === 'A' && el.hasAttribute('href')) return 'link';
          if (tag === 'BUTTON' || tag === 'SUMMARY') return 'button';
          if (tag === 'INPUT') {
            if (['button', 'submit', 'reset', 'image'].includes(type)) return 'button';
            if (type === 'checkbox') return 'checkbox';
            if (type === 'radio') return 'radio';
            if (type === 'range') return 'slider';
            if (type === 'number') return 'spinbutton';
            if (type === 'search') return 'searchbox';
            if (type === 'hidden') return '';
            return 'textbox';
          }
          if (tag === 'TEXTAREA') return 'textbox';
          if (tag === 'SELECT') return el.multiple ? 'listbox' : 'combobox';
          if (tag === 'OPTION') return 'option';
          if (/^H[1-6]$/.test(tag)) return 'heading';
          if (tag === 'IMG') return el.getAttribute('alt') === '' ? '' : 'img';
          if (tag === 'NAV') return 'navigation';
          if (tag === 'MAIN') return 'main';
          if (tag === 'FORM') return 'form';
          if (tag === 'DIALOG') return 'dialog';
          if (tag === 'UL' || tag === 'OL') return 'list';
          if (tag === 'LI') return 'listitem';
          if (tag === 'TABLE') return 'table';
          if (tag === 'TR') return 'row';
          if (tag === 'TD') return 'cell';
          if (tag === 'TH') return 'columnheader';
          if (el.isContentEditable && el.parentElement && !el.parentElement.isContentEditable) return 'textbox';
          return '';
        }

        function clip(text, n) {
          const t = (text || '').replace(/\s+/g, ' ').trim();
          return t.length > n ? t.slice(0, n) + '…' : t;
        }

        function name(el) {
          const label = el.getAttribute('aria-label');
          if (label) return clip(label, 80);
          const by = el.getAttribute('aria-labelledby');
          if (by) {
            const text = by.split(/\s+/).map(id => { const n = document.getElementById(id); return n ? n.innerText : ''; }).join(' ');
            if (text.trim()) return clip(text, 80);
          }
          if (el.labels && el.labels.length) return clip(el.labels[0].innerText, 80);
          if (el.tagName === 'IMG') return clip(el.getAttribute('alt'), 80);
          if (el.tagName === 'INPUT' && ['button', 'submit', 'reset'].includes(el.type)) return clip(el.value, 80);
          const own = ['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName) ? '' : el.innerText;
          return clip(own || el.getAttribute('title') || el.getAttribute('placeholder') || '', 80);
        }

        function state(el, r) {
          const out = [];
          if (r === 'heading') out.push('level=' + (el.tagName.match(/\d/) || [el.getAttribute('aria-level') || '2'])[0]);
          if (el.disabled || el.getAttribute('aria-disabled') === 'true') out.push('disabled');
          if (el.checked || el.getAttribute('aria-checked') === 'true') out.push('checked');
          if (el.getAttribute('aria-expanded') === 'true') out.push('expanded');
          if (el.getAttribute('aria-selected') === 'true' || (el.tagName === 'OPTION' && el.selected)) out.push('selected');
          if (el === document.activeElement) out.push('focused');
          if (el.required) out.push('required');
          return out;
        }

        function value(el, r) {
          if (!['textbox', 'searchbox', 'combobox', 'spinbutton', 'slider'].includes(r)) return null;
          if (el.tagName === 'SELECT') return el.selectedOptions.length ? clip(el.selectedOptions[0].innerText, 80) : '';
          if (el.type === 'password') return el.value ? '••••' : '';
          if (el.isContentEditable) return clip(el.innerText, 120);
          return clip(el.value, 120);
        }

        function snapshot(maxNodes, maxBytes) {
          refs = new Map();
          let next = 1, count = 0, bytes = 0, cut = 0;
          const lines = [];
          function add(line) {
            if (count >= maxNodes || bytes + line.length > maxBytes) { cut++; return false; }
            lines.push(line); count++; bytes += line.length + 1;
            return true;
          }
          function walk(node, depth) {
            for (const child of node.children || []) {
              if (SKIP.has(child.tagName)) continue;
              if (!shown(child)) continue;
              const r = role(child);
              let deeper = depth;
              if (ACTIVE.has(r) || CONTEXT.has(r)) {
                let line = '  '.repeat(depth) + '- ' + r;
                const n = name(child);
                if (n) line += ' ' + JSON.stringify(n);
                const v = value(child, r);
                if (v !== null) line += ' value=' + JSON.stringify(v);
                const s = state(child, r);
                if (s.length) line += ' [' + s.join(', ') + ']';
                if (ACTIVE.has(r) && !child.disabled) {
                  const ref = 'e' + (next++);
                  refs.set(ref, child);
                  line += ' [@' + ref + ']';
                }
                add(line);
                deeper = depth + 1;
                if (ACTIVE.has(r) && r !== 'listbox' && r !== 'combobox') continue;
              } else if (!child.children.length) {
                const t = clip(child.innerText, 80);
                if (t) add('  '.repeat(depth) + '- text ' + JSON.stringify(t));
                continue;
              }
              walk(child, deeper);
              if (child.shadowRoot) walk(child.shadowRoot, deeper);
            }
          }
          if (document.body) walk(document.body, 0);
          return { title: document.title, url: location.href, text: lines.join('\n'), count, cut };
        }

        function element(ref) {
          const el = refs.get(ref);
          return el && el.isConnected ? el : null;
        }

        function box(ref) {
          const el = element(ref);
          if (!el) return { error: 'stale' };
          el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
          const r = el.getBoundingClientRect();
          return { x: r.left, y: r.top, w: r.width, h: r.height, vw: innerWidth, vh: innerHeight };
        }

        function prepareFill(ref) {
          const el = element(ref);
          if (!el) return { error: 'stale' };
          el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
          el.focus();
          if (typeof el.select === 'function') el.select();
          else if (el.isContentEditable) {
            const range = document.createRange();
            range.selectNodeContents(el);
            const sel = getSelection(); sel.removeAllRanges(); sel.addRange(range);
          }
          return { focused: document.activeElement === el, filled: !!(el.value || (el.isContentEditable && el.innerText.trim())) };
        }

        function exists(selector) {
          try { const el = document.querySelector(selector); return !!el && shown(el); } catch (e) { return null; }
        }

        function scrollBy(dy) { window.scrollBy(0, dy * innerHeight); return { y: scrollY }; }

        return { snapshot, box, prepareFill, exists, scrollBy };
      })();
    }
    """#
}
