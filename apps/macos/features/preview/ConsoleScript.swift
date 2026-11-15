/// The page's console for the agent (docs/adr/0025-agent-drives-preview.md):
/// errors and messages the page writes, kept in a buffer in the page's own
/// world, since only a script there sees its console. Injected by
/// evaluateJavaScript when the agent takes the tab and again after each
/// navigation, never a `WKUserScript`; with no agent, nothing of it exists.
/// The page can see and fake the buffer: what comes back is page content,
/// never instructions.
enum ConsoleScript {
    static let install = #"""
    (() => {
      if (window.__cadexConsole) return true;
      const buffer = [];
      window.__cadexConsole = buffer;
      const keep = (level, parts) => {
        const text = parts.map(p => {
          if (p instanceof Error) return p.name + ': ' + p.message;
          if (typeof p === 'string') return p;
          try { return JSON.stringify(p); } catch (e) { return String(p); }
        }).join(' ');
        buffer.push(level + ': ' + text.slice(0, 300));
        if (buffer.length > 200) buffer.splice(0, buffer.length - 200);
      };
      for (const level of ['error', 'warn', 'log', 'info']) {
        const original = console[level];
        console[level] = function (...parts) { keep(level, parts); return original.apply(this, parts); };
      }
      window.addEventListener('error', e => {
        keep('error', [(e.message || 'error') + (e.filename ? ' at ' + e.filename.split('/').pop() + ':' + e.lineno : '')]);
      });
      window.addEventListener('unhandledrejection', e => {
        const r = e.reason;
        keep('error', ['unhandled rejection: ' + (r && r.message ? r.message : String(r))]);
      });
      return true;
    })()
    """#

    /// The lines since the last read, at most `limit`; the buffer empties.
    static func read(limit: Int) -> String {
        "JSON.stringify((window.__cadexConsole || []).splice(0).slice(-\(limit)))"
    }
}
