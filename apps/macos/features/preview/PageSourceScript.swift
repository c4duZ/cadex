/// Where a picked element comes from, read in the page's own world once per
/// click (docs/adr/0018-element-picker.md): what frameworks hang on the
/// node in development is JavaScript, which the picker's world cannot see.
/// Finds the element by the one-time mark the picker's world set, takes the
/// mark off and answers JSON `{source, components}`. The page could fake
/// the answer: it is page content like the rest, cut and cleaned in Swift.
enum PageSourceScript {
    /// The body of an async function with the argument `mark`
    /// (callAsyncJavaScript).
    static let body = #"""
    const el = document.querySelector('[data-cadex-pick="' + mark + '"]');
    if (!el) return null;
    el.removeAttribute('data-cadex-pick');
    const out = { source: null, components: [] };
    const at = (file, line, column) =>
      file ? file + (line ? ':' + line + (column ? ':' + column : '') : '') : null;
    // Framework parts, not the app's components.
    const internal = /(Provider|Consumer|Context|Boundary|Router|Handler)$|^(Suspense|Fragment|StrictMode|Profiler|Routes|Route|Outlet|HotReload|ServerRoot|Root|Anonymous)$/;
    const add = (name) => {
      if (name && /^[A-Z]/.test(name) && !internal.test(name) && out.components[out.components.length - 1] !== name)
        out.components.push(name);
    };

    // lovable-tagger: the JSX position of the element.
    const jsx = el[Symbol.for('__jsxSource__')];
    if (jsx && jsx.fileName) out.source = at(jsx.fileName, jsx.lineNumber, jsx.columnNumber);

    // Svelte in development: 0-based line and column, as its inspector reads them.
    for (let node = el; node && !out.source; node = node.parentElement) {
      const loc = node.__svelte_meta && node.__svelte_meta.loc;
      if (loc && loc.file) out.source = at(loc.file, loc.line + 1, loc.column + 1);
    }

    // React: the fiber on the node. Up to 18, _debugSource is where the
    // element was written; 19 dropped it (plan 16, phase C).
    const key = Object.keys(el).find((k) => k.startsWith('__reactFiber$') || k.startsWith('__reactInternalInstance$'));
    const fiber = key ? el[key] : null;
    if (fiber) {
      for (let f = fiber, n = 0; f && !out.source && n < 50; f = f._debugOwner, n++) {
        const s = f._debugSource;
        if (s && s.fileName) out.source = at(s.fileName, s.lineNumber, s.columnNumber);
      }
      for (let f = fiber.return, n = 0; f && out.components.length < 4 && n < 500; f = f.return, n++) {
        const t = f.type;
        if (typeof t === 'function') add(t.displayName || t.name);
        else if (t && typeof t === 'object')
          add(t.displayName || (t.render && (t.render.displayName || t.render.name)) || (t.type && (t.type.displayName || t.type.name)));
      }
    }

    // Vue 3: the component's file, and the components up the tree.
    const vue = el.__vueParentComponent;
    if (vue) {
      if (!out.source && vue.type && vue.type.__file) out.source = vue.type.__file;
      for (let i = vue, n = 0; i && out.components.length < 4 && n < 200; i = i.parent, n++) {
        const t = i.type || {};
        add(t.name || t.__name || (t.__file && t.__file.split('/').pop().replace(/\.vue$/, '')));
      }
    }
    return JSON.stringify(out);
    """#
}
