import Foundation

/// One container of a machine, as `docker ps --all --format '{{json .}}'` says.
public struct DockerContainer: Equatable, Sendable {
    public var name: String
    public var image: String
    /// "running", "exited"...
    public var state: String
    /// "Up 3 hours", "Exited (0) 2 days ago".
    public var status: String
    /// The ports published on the machine (what the preview can open).
    public var ports: [Int]
}

/// The owner's `docker`, driven for another machine (docs/spec/machines.md,
/// Docker pela tailnet; ADR 0032): a context per machine, `ssh://` to it,
/// chosen per tab with DOCKER_CONTEXT and never with `docker context use`,
/// which would move every terminal of the owner. Cadex has no Docker client
/// of its own and installs nothing; without the binary, it says so.
public enum Docker {
    public static let candidates = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker",
                                    "/Applications/Docker.app/Contents/Resources/bin/docker"]

    public static func binary() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The context's name: the machine's short name, as the spec says (`pc`).
    public static func contextName(_ machine: Machine) -> String { machine.name }

    public static func createArguments(name: String, destination: String) -> [String] {
        ["context", "create", name, "--description", "Cadex: \(destination) over the tailnet", "--docker", "host=ssh://\(destination)"]
    }

    /// The names in `docker context ls --format '{{json .}}'`.
    public static func contextNames(_ output: String) -> [String] {
        lines(output).compactMap { $0["Name"] as? String }
    }

    public static func containers(_ output: String) -> [DockerContainer] {
        lines(output).compactMap { row in
            guard let name = row["Names"] as? String else { return nil }
            return DockerContainer(name: name, image: row["Image"] as? String ?? "", state: row["State"] as? String ?? "",
                                   status: row["Status"] as? String ?? "", ports: publishedPorts(row["Ports"] as? String ?? ""))
        }
    }

    /// "0.0.0.0:3000->3000/tcp, :::3000->3000/tcp, 5432/tcp" → [3000]: only
    /// the ports bound on the machine, once each (IPv4 and IPv6 repeat).
    public static func publishedPorts(_ text: String) -> [Int] {
        var ports: [Int] = []
        for part in text.split(separator: ",") {
            guard let arrow = part.range(of: "->") else { continue }
            let bound = part[..<arrow.lowerBound]
            guard let colon = bound.lastIndex(of: ":"), let port = Int(bound[bound.index(after: colon)...]),
                  !ports.contains(port) else { continue }
            ports.append(port)
        }
        return ports
    }

    /// `docker exec -it <name>` with bash when it has one, else sh.
    public static func shellLine(context: String, container: String) -> String {
        let q = { (text: String) in "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return "docker --context \(q(context)) exec -it \(q(container)) sh -c 'command -v bash >/dev/null && exec bash || exec sh'"
    }

    /// What the tab types to use a context, or this Mac's Docker with nil.
    public static func exportLine(_ context: String?) -> String {
        guard let context else { return "unset DOCKER_CONTEXT" }
        return "export DOCKER_CONTEXT='" + context.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The context for `machine` exists, made if it did not; nil, or the
    /// error docker gave.
    public static func ensureContext(_ machine: Machine, destination: String) async -> String? {
        guard let docker = binary() else { return notInstalled }
        let name = contextName(machine)
        let list = await run(docker, ["context", "ls", "--format", "{{json .}}"])
        if list.status == 0, contextNames(list.out).contains(name) { return nil }
        let made = await run(docker, createArguments(name: name, destination: destination))
        return made.status == 0 ? nil : made.err.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func containers(on machine: Machine) async -> Result<[DockerContainer], DockerError> {
        guard let docker = binary() else { return .failure(.message(notInstalled)) }
        let result = await run(docker, ["--context", contextName(machine), "ps", "--all", "--format", "{{json .}}"], timeout: 20)
        guard result.status == 0 else { return .failure(.message(result.err.trimmingCharacters(in: .whitespacesAndNewlines))) }
        return .success(containers(result.out))
    }

    public static let notInstalled = "Docker is not installed on this Mac."

    static func lines(_ output: String) -> [[String: Any]] {
        output.split(separator: "\n").compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
    }

    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 10) async -> (status: Int32, out: String, err: String) {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            guard (try? process.run()) != nil else { return (-1, "", "docker could not start") }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
            let errText = ErrBuffer()
            let reader = Thread { errText.data = err.fileHandleForReading.readDataToEndOfFile() }
            reader.start()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            while !reader.isFinished { usleep(1000) }
            return (process.terminationStatus, String(decoding: data, as: UTF8.self), String(decoding: errText.data, as: UTF8.self))
        }.value
    }
}

public enum DockerError: Error, Equatable {
    case message(String)
}

final class ErrBuffer: @unchecked Sendable {
    var data = Data()
}
