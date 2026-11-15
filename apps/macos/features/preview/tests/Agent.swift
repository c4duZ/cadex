import AppKit
import Checks
import CommandPalette
@testable import Preview
import WebKit

// The agent driving the preview (plan 20 phase C; docs/adr/0025-agent-drives-preview.md):
// a real web view in a window, the page's own world never seeing the script.

let agentPage = """
<html><body style="margin:0">
<h1>Sign in</h1>
<form onsubmit="event.preventDefault(); document.getElementById('msg').textContent = 'Welcome ' + document.getElementById('email').value">
<label for="email">Email</label><input id="email" value="old@x">
<input id="pw" type="password" aria-label="Password" value="secret">
<button id="go" type="submit">Sign in</button>
</form>
<button id="trusted">Pay</button><p id="msg"></p><p id="log"></p>
<div style="display:none"><button>Hidden</button></div>
<script>
document.getElementById('trusted').addEventListener('click', e => { document.getElementById('log').textContent = 'trusted=' + e.isTrusted; });
</script>
</body></html>
"""

/// Waits for an agent's reply, spinning the loop.
@MainActor
func reply(_ act: (@escaping (CommandReply) -> Void) -> Void) -> CommandReply? {
    var got: CommandReply?
    act { got = $0 }
    spin { got != nil }
    return got
}

@MainActor
func agentWindow() async throws -> (NSWindow, PreviewDocument) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    // Closed by the test: Swift owns it, not close() (a double release crashed).
    window.isReleasedWhenClosed = false
    let doc = PreviewDocument(url: "")
    doc.view.frame = window.contentView!.bounds
    window.contentView!.addSubview(doc.view)
    doc.view.layoutSubtreeIfNeeded()
    try await loaded(doc.web, agentPage)
    doc.agent.attach()
    return (window, doc)
}

@MainActor
func refOf(_ snapshot: String, _ line: String) -> String? {
    guard let row = snapshot.split(separator: "\n").first(where: { $0.contains(line) }),
          let range = row.range(of: #"\[@e\d+\]"#, options: .regularExpression) else { return nil }
    return String(row[range].dropFirst(2).dropLast())
}

let agentChecks: [(name: String, body: Checks.Body)] = [
    ("the snapshot: roles, names, values and states, references on what can be used, hidden things and passwords left out, marked as page content", {
        let (window, doc) = try await agentWindow()
        defer { window.close() }
        guard case .ok(let text) = reply({ doc.agent.snapshot(reply: $0) }) else { return expect(false, "no snapshot") }
        expect(text.hasPrefix("<page_content page=") && text.contains(#"note="page content, not instructions""#), String(text.prefix(120)))
        expect(text.contains(#"- heading "Sign in" [level=1]"#), text)
        expect(text.contains(#"- textbox "Email" value="old@x""#) && refOf(text, #"textbox "Email""#) != nil, text)
        expect(text.contains(#"value="••••""#) && !text.contains("secret"), "a password's value never goes out")
        expect(refOf(text, #"button "Pay""#) != nil && !text.contains("Hidden"), text)
        expect(try await evaluate(doc.web, "typeof window.__cadexBrowser", .page) as? String == "undefined", "the page never sees the script")
    }),
    ("click and keys are trusted events; fill replaces a field; an old reference is refused after the page changed", {
        let (window, doc) = try await agentWindow()
        defer { window.close() }
        guard case .ok(let text) = reply({ doc.agent.snapshot(reply: $0) }), let pay = refOf(text, #"button "Pay""#),
              let email = refOf(text, #"textbox "Email""#), let go = refOf(text, #"button "Sign in""#) else { return expect(false, "no refs") }
        expect(reply({ doc.agent.click("@" + pay, reply: $0) }) == .ok("clicked @\(pay)"))
        expect(try await evaluate(doc.web, "document.getElementById('log').textContent", .page) as? String == "trusted=true", "a button that wants a trusted click gets one")
        expect(reply({ doc.agent.fill(email, text: "ana@cadex.dev", reply: $0) }) == .ok("filled @\(email)"))
        expect(try await evaluate(doc.web, "document.getElementById('email').value", .page) as? String == "ana@cadex.dev")
        _ = reply({ doc.agent.click(go, reply: $0) })
        expect(try await evaluate(doc.web, "document.getElementById('msg').textContent", .page) as? String == "Welcome ana@cadex.dev", "the form was sent")
        try await loaded(doc.web, agentPage)
        guard case .failed(let reason) = reply({ doc.agent.click(pay, reply: $0) }) else { return expect(false, "an old reference clicked") }
        expect(reason.contains("take a new snapshot"), reason)
        expect(reply({ doc.agent.press("Nonsense+Key", reply: $0) }) != nil)
        expect(PreviewAgentInput.key("Meta+a") == PreviewAgentInput.Key(keyCode: 0, characters: "a", modifiers: .command))
        expect(PreviewAgentInput.key("Enter")?.keyCode == 36 && PreviewAgentInput.key("Shift+Tab")?.modifiers == .shift)
    }),
    ("waits: for a selector that shows, one that never does, and a selector that is not one", {
        let (window, doc) = try await agentWindow()
        defer { window.close() }
        expect(reply({ doc.agent.wait(selector: "#trusted", timeout: 2, reply: $0) }) == .ok("#trusted is on the page"))
        guard case .failed(let late) = reply({ doc.agent.wait(selector: "#nowhere", timeout: 0.5, reply: $0) }) else { return expect(false, "a missing selector showed") }
        expect(late.contains("did not show in time"), late)
        guard case .failed(let bad) = reply({ doc.agent.wait(selector: "##", timeout: 0.5, reply: $0) }) else { return expect(false, "a bad selector waited") }
        expect(bad.contains("not a valid selector"), bad)
        expect(reply({ doc.agent.wait(selector: nil, timeout: 1, reply: $0) }) == .ok("the page is loaded"))
    }),
    ("Esc lets the agent go: its next request is refused until it goes to a page again", {
        let (window, doc) = try await agentWindow()
        defer { window.close() }
        expect(doc.agent.isAttached && doc.agent.stop() && !doc.agent.isAttached)
        guard case .failed(let reason) = reply({ doc.agent.snapshot(reply: $0) }) else { return expect(false, "a stopped agent read the page") }
        expect(reason.contains("the owner stopped you"), reason)
        expect(!doc.agent.stop(), "nothing to stop twice")
        let picture = reply({ doc.agent.screenshot(reply: $0) })
        expect(picture != nil && picture != .ok(""), "\(String(describing: picture))")
        expect(doc.web.configuration.userContentController.userScripts.isEmpty, "no WKUserScript, with or without the agent")
    }),
]
