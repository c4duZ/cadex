import Foundation

/// A task's throwaway environment (docs/adr/0032-workspace-recipes.md): a
/// container made from the repository's recipe where the task's worktree
/// is (this Mac's docker, or the task's machine through its Docker
/// context), with the worktree mounted; it suspends, resumes and goes with
/// the task. Kept in the notes, never anything secret.
public struct TaskEnvironment: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case running, suspended }

    public var container: String
    /// The Tailscale sidecar's container, when the recipe asks one.
    public var sidecar: String?
    /// The Docker context of the task's machine; nil on this Mac.
    public var context: String?
    public var state: State = .running

    /// Every container of it, the sidecar first (the other shares its network).
    public var containers: [String] { (sidecar.map { [$0] } ?? []) + [container] }
}

/// The docker commands of an environment, pure and tested with a fake
/// docker. Bringing one up is typed in a tab (its output in sight, and the
/// sidecar's key read from the owner's own shell, never by Cadex); the rest
/// runs in the background with the owner's docker.
public enum EnvironmentScript {
    /// `cadex-<repo>-<branch>`, in the letters Docker takes in a name.
    public static func name(repo: String, branch: String) -> String {
        let raw = "cadex-" + (repo as NSString).lastPathComponent + "-" + branch
        let kept = raw.lowercased().map { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "-" }
        return String(String(kept).prefix(120))
    }

    public static func environment(recipe: EnvironmentRecipe, repo: String, branch: String, context: String?) -> TaskEnvironment {
        let container = name(repo: repo, branch: branch)
        return TaskEnvironment(container: container, sidecar: recipe.tailscaleName.isEmpty ? nil : container + "-ts", context: context)
    }

    static func docker(_ context: String?) -> String {
        context.map { "docker --context " + RemoteTaskScript.quote($0) } ?? "docker"
    }

    /// The tab's script (run as `sh -c`, so a failure ends it, not the tab):
    /// the image (pulled, or built from the Dockerfile on this Mac), the
    /// sidecar with the key from `$<authkey_env>`, the container with the
    /// worktree at `workdir`, the setup, then `claude` inside (a shell if the
    /// image has none).
    public static func up(_ recipe: EnvironmentRecipe, _ env: TaskEnvironment, worktree: String) -> String {
        let q = RemoteTaskScript.quote
        let d = docker(env.context)
        var lines = ["set -e"]
        if env.sidecar != nil {
            let variable = recipe.authKeyVariable
            lines.append("[ -n \"${\(variable):-}\" ] || { echo \(q("Cadex: $\(variable) is not set in this shell; the Tailscale sidecar needs it.")); exit 1; }")
        }
        var image = q(recipe.image)
        if !recipe.dockerfile.isEmpty {
            let tag = env.container + "-image"
            lines.append("\(d) build -t \(q(tag)) -f \(q(worktree + "/" + recipe.dockerfile)) \(q(worktree))")
            image = q(tag)
        }
        let ports = recipe.ports.map { "-p \($0):\($0)" }.joined(separator: " ")
        var network = ports
        if let sidecar = env.sidecar {
            let name = q(recipe.tailscaleName)
            lines.append("TS_AUTHKEY=\"$\(recipe.authKeyVariable)\" \(d) run -d --name \(q(sidecar)) --hostname \(name) -e TS_AUTHKEY -e TS_HOSTNAME=\(name) -e TS_STATE_DIR=/var/lib/tailscale -e TS_USERSPACE=true \(ports) tailscale/tailscale".replacingOccurrences(of: "  ", with: " "))
            network = "--network container:" + q(sidecar)
        }
        let keepAlive = q("trap exit TERM; while :; do sleep 3600 & wait; done")
        lines.append("\(d) run -d --name \(q(env.container)) --label cadex.task=\(q(worktree)) -v \(q(worktree + ":" + recipe.workdir)) -w \(q(recipe.workdir)) \(network) \(image) sh -c \(keepAlive)".replacingOccurrences(of: "  ", with: " "))
        if !recipe.setup.isEmpty { lines.append("\(d) exec \(q(env.container)) sh -c \(q(recipe.setup))") }
        let agent = "command -v claude >/dev/null && exec claude || { echo 'Cadex: no claude in this container; the recipe setup can install it.'; exec sh -l; }"
        lines.append("exec \(d) exec -it \(q(env.container)) sh -lc \(q(agent))")
        return lines.joined(separator: "\n")
    }

    /// What the tab types: the script, in its own sh.
    public static func upLine(_ recipe: EnvironmentRecipe, _ env: TaskEnvironment, worktree: String) -> String {
        "sh -c " + RemoteTaskScript.quote(up(recipe, env, worktree: worktree))
    }

    /// docker's arguments to stop (suspend), start (resume) and remove
    /// (destroy) it: stopped, it holds no memory or CPU, and its files stay.
    public static func suspend(_ env: TaskEnvironment) -> [String] { prefix(env) + ["stop"] + env.containers.reversed() }
    public static func resume(_ env: TaskEnvironment) -> [String] { prefix(env) + ["start"] + env.containers }
    public static func destroy(_ env: TaskEnvironment) -> [String] { prefix(env) + ["rm", "-f"] + env.containers }

    static func prefix(_ env: TaskEnvironment) -> [String] { env.context.map { ["--context", $0] } ?? [] }
}
