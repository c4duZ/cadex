import Checks
import Foundation
@testable import Worktrees

// A task's throwaway environment (plan 23, phase E; ADR 0032): the recipe
// read, and the docker commands run against a fake docker that writes down
// every call, never a real container.

/// A fake `docker` in `dir/bin` writing each call's arguments, one per
/// line and calls split by "--", to `dir/docker.log`.
func fakeDocker(_ dir: String) -> String {
    let bin = dir + "/bin"
    try? fm.createDirectory(atPath: bin, withIntermediateDirectories: true)
    fm.createFile(atPath: bin + "/docker", contents: Data("#!/bin/sh\nfor a; do printf '%s\\n' \"$a\"; done >> \"$LOG\"\necho -- >> \"$LOG\"\n".utf8),
                  attributes: [.posixPermissions: 0o755])
    return bin
}

func dockerCalls(_ dir: String) -> [[String]] {
    let text = (try? String(contentsOfFile: dir + "/docker.log", encoding: .utf8)) ?? ""
    return text.components(separatedBy: "--\n").map { $0.split(separator: "\n").map(String.init) }.filter { !$0.isEmpty }
}

let fullRecipe = """
# the app's environment
image = "node:22"
machine = "pc"
ports = [3000, 5_173]   # dev servers
setup = "npm ci && echo \\"ready\\""
[tailscale]
name = "ubuntu-dev"
authkey_env = "MY_TS_KEY"
"""

let environmentTests: [(name: String, body: Checks.Body)] = [
    ("the recipe: every field, comments, and errors with their line, never half a recipe", {
        guard case .success(let recipe) = EnvironmentRecipe.parse(fullRecipe) else { return expect(false, "\(EnvironmentRecipe.parse(fullRecipe))") }
        expect(recipe.image == "node:22" && recipe.machine == "pc" && recipe.ports == [3000, 5173] && recipe.workdir == "/work")
        expect(recipe.setup == "npm ci && echo \"ready\"" && recipe.tailscaleName == "ubuntu-dev" && recipe.authKeyVariable == "MY_TS_KEY")
        expect(EnvironmentRecipe.parse("image = 'a#b' # c") == .success(EnvironmentRecipe(image: "a#b")), "a # in quotes is not a comment")
        expect(EnvironmentRecipe.parse("image = \"x\"\nport = 3") == .failure(RecipeError(line: 2, message: "unknown key port")))
        expect(EnvironmentRecipe.parse("image = x") == .failure(RecipeError(line: 1, message: "image: a value TOML reads")))
        expect(EnvironmentRecipe.parse("image = \"x\"\nports = [\"80\"]") == .failure(RecipeError(line: 2, message: "ports is a list of port numbers")))
        expect(EnvironmentRecipe.parse("setup = \"x\"").failureMessage == "either image or dockerfile, one of them")
        expect(EnvironmentRecipe.parse("image = \"x\"\n[db]\n").failureMessage == "line 2: unknown table [db]")
        expect(EnvironmentRecipe.parse("image = \"x\"\n[tailscale]\nauthkey_env = \"$(rm -rf)\"").failureMessage == "line 3: authkey_env is a variable's name")
    }),
    ("bringing it up: sidecar with the key from the owner's shell, the container on its network with the worktree, setup, claude", {
        let (home, repo) = fakeRepo()
        defer { try? fm.removeItem(atPath: home) }
        guard case .success(let recipe) = EnvironmentRecipe.parse(fullRecipe) else { return expect(false) }
        let env = EnvironmentScript.environment(recipe: recipe, repo: repo, branch: "Fix/Login", context: "pc")
        expect(env.container == "cadex-app-fix-login" && env.sidecar == "cadex-app-fix-login-ts" && env.containers.first == env.sidecar)
        let bin = fakeDocker(home)
        let script = EnvironmentScript.upLine(recipe, env, worktree: repo + "/it's")
        _ = sh(script, env: ["PATH": bin + ":/usr/bin:/bin", "LOG": home + "/docker.log", "MY_TS_KEY": "tskey-secret"])
        let calls = dockerCalls(home)
        expect(calls.count == 4, "\(calls)")
        expect(calls[0].prefix(6) == ["--context", "pc", "run", "-d", "--name", "cadex-app-fix-login-ts"] && calls[0].contains("TS_AUTHKEY")
               && calls[0].contains("TS_HOSTNAME=ubuntu-dev") && calls[0].contains("3000:3000") && calls[0].last == "tailscale/tailscale", "\(calls[0])")
        expect(!calls.joined().joined().contains("tskey-secret"), "the key goes by the environment, never in the arguments")
        expect(calls[1].contains("container:cadex-app-fix-login-ts") && calls[1].contains(repo + "/it's:/work") && calls[1].contains("node:22")
               && !calls[1].contains("3000:3000"), "\(calls[1]): the ports are the sidecar's")
        expect(calls[2] == ["--context", "pc", "exec", "cadex-app-fix-login", "sh", "-c", "npm ci && echo \"ready\""], "\(calls[2])")
        expect(calls[3].prefix(6) == ["--context", "pc", "exec", "-it", "cadex-app-fix-login", "sh"] && calls[3].last?.contains("exec claude") == true)
    }),
    ("no key in the shell: it says which variable and starts nothing; no sidecar asked, no key needed", {
        let (home, repo) = fakeRepo()
        defer { try? fm.removeItem(atPath: home) }
        guard case .success(let recipe) = EnvironmentRecipe.parse(fullRecipe) else { return expect(false) }
        let env = EnvironmentScript.environment(recipe: recipe, repo: repo, branch: "x", context: nil)
        let bin = fakeDocker(home)
        let out = sh(EnvironmentScript.upLine(recipe, env, worktree: repo), env: ["PATH": bin + ":/usr/bin:/bin", "LOG": home + "/docker.log"])
        expect(out.contains("$MY_TS_KEY is not set") && dockerCalls(home).isEmpty, out)
        let plain = EnvironmentRecipe(dockerfile: "Dockerfile.dev")
        let local = EnvironmentScript.environment(recipe: plain, repo: repo, branch: "y", context: nil)
        _ = sh(EnvironmentScript.upLine(plain, local, worktree: repo), env: ["PATH": bin + ":/usr/bin:/bin", "LOG": home + "/docker.log"])
        let calls = dockerCalls(home)
        expect(calls.first?.prefix(4) == ["build", "-t", "cadex-app-y-image", "-f"] && calls[1].contains("cadex-app-y-image"), "\(calls)")
        expect(local.sidecar == nil && !calls[1].contains(where: { $0.hasPrefix("container:") }))
    }),
    ("suspend, resume and destroy: the sidecar started first and stopped last; the context kept", {
        let env = TaskEnvironment(container: "c", sidecar: "c-ts", context: "pc")
        expect(EnvironmentScript.suspend(env) == ["--context", "pc", "stop", "c", "c-ts"])
        expect(EnvironmentScript.resume(env) == ["--context", "pc", "start", "c-ts", "c"])
        expect(EnvironmentScript.destroy(TaskEnvironment(container: "c")) == ["rm", "-f", "c"])
        let (home, _) = fakeRepo()
        defer { try? fm.removeItem(atPath: home) }
        let store = WorktreesStore(path: home + "/notes.json")
        store.setEnvironment(env, for: "/t")
        expect(WorktreesStore(path: home + "/notes.json").environment("/t") == env, "kept in the notes")
    }),
]

extension Result where Failure == RecipeError {
    var failureMessage: String? { if case .failure(let error) = self { error.description } else { nil } }
}
