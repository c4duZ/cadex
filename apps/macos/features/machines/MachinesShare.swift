import Foundation

/// `tailscale serve`/`funnel` for one local server (docs/spec/machines.md).
extension MachinesController {
    /// Shares `localPort` on the first free HTTPS port of this Mac's
    /// tailnet name; the address, or why not. A port the owner serves is
    /// never taken; the share is kept so it can be undone.
    public func share(localPort: Int, isPublic: Bool) async -> Result<String, DockerError> {
        guard isEnabled, let cli = daemon.cli() else { return .failure(.message("Tailscale is not running.")) }
        if status == nil { await withCheckedContinuation { done in refresh { done.resume() } } }
        guard let me = status?.machines.first(where: \.isSelf), !me.dnsName.isEmpty else {
            return .failure(.message("This Mac has no MagicDNS name on the tailnet (turn MagicDNS and HTTPS on in the admin console)."))
        }
        if isPublic, status?.funnelAllowed != true { return .failure(.message("Your tailnet does not let this Mac use Funnel.")) }
        let runner = shareRunner
        let used = await Task.detached { runner(cli, ["serve", "status", "--json"]).map(TailscaleServe.usedPorts) ?? [] }.value
        guard let https = TailscaleServe.freePort(used: used) else { return .failure(.message("Ports 443, 8443 and 10000 are all served already.")) }
        let share = TailnetShare(httpsPort: https, localPort: localPort, isPublic: isPublic)
        guard await Task.detached(operation: { runner(cli, TailscaleServe.shareArguments(share)) }).value != nil else {
            return .failure(.message("tailscale \(isPublic ? "funnel" : "serve") did not start; HTTPS may be off for the tailnet."))
        }
        shares.add(share)
        return .success(TailscaleServe.url(dnsName: me.dnsName, httpsPort: https))
    }

    /// Turns off what Cadex turned on at that port; nil when done.
    public func stopSharing(_ share: TailnetShare) async -> String? {
        guard let cli = daemon.cli() else { return "Tailscale is not running." }
        let runner = shareRunner
        guard await Task.detached(operation: { runner(cli, TailscaleServe.stopArguments(share)) }).value != nil else {
            return "tailscale did not stop it."
        }
        shares.remove(share)
        return nil
    }

    nonisolated static func runCLI(_ cli: (path: String, beCLI: Bool), _ args: [String]) -> Data? {
        LocalAPI.cli(cli.path, beCLI: cli.beCLI, args)
    }
}
