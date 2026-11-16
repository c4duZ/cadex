import Checks
import Foundation
@testable import Machines

// Docker through the tailnet (plan 23, phase D; ADR 0032): what Cadex asks
// the owner's docker and how it reads the answers. `docker context ls`'s
// keys were read on this Mac (2026-11-16); `docker ps`'s are the documented
// `{{json .}}` fields.

func run(_ text: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", text]
    let out = Pipe()
    process.standardOutput = out
    try? process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

let dockerTests: [(name: String, body: Checks.Body)] = [
    ("contexts: one per machine, ssh to it, never `docker context use`", {
        let pc = Tailnet.status(Data(statusRunning.utf8))!.others.first { $0.name == "pc" }!
        expect(Docker.contextName(pc) == "pc")
        let args = Docker.createArguments(name: "pc", destination: "dev@pc.tail1234.ts.net")
        expect(args == ["context", "create", "pc", "--description", "Cadex: dev@pc.tail1234.ts.net over the tailnet", "--docker", "host=ssh://dev@pc.tail1234.ts.net"], "\(args)")
        expect(!args.contains("use"))
        let ls = #"{"Current":false,"Description":"","DockerEndpoint":"unix:///var/run/docker.sock","Error":"","Name":"default"}"# + "\n"
            + #"{"Current":true,"Description":"Cadex","DockerEndpoint":"ssh://dev@pc","Error":"","Name":"pc"}"#
        expect(Docker.contextNames(ls) == ["default", "pc"])
        expect(run(Docker.exportLine("it's") + "; printf %s \"$DOCKER_CONTEXT\"") == "it's", "the tab's shell gets the name as it is")
        expect(run("DOCKER_CONTEXT=pc; " + Docker.exportLine(nil) + "; printf %s \"${DOCKER_CONTEXT-unset}\"") == "unset")
    }),
    ("containers: name, image, state, and the ports published on the machine, once each", {
        let ps = #"{"Command":"\"npm run dev\"","ID":"a1","Image":"node:22","Names":"web","Ports":"0.0.0.0:3000->3000/tcp, :::3000->3000/tcp, 9229/tcp","State":"running","Status":"Up 3 hours"}"# + "\n"
            + #"{"ID":"b2","Image":"postgres:17","Names":"db","Ports":"127.0.0.1:5432->5432/tcp","State":"exited","Status":"Exited (0) 2 days ago"}"# + "\n"
            + "not json\n" + #"{"ID":"c3"}"#
        let containers = Docker.containers(ps)
        expect(containers.map(\.name) == ["web", "db"], "a row without a name is skipped")
        expect(containers[0].ports == [3000] && containers[0].image == "node:22" && containers[0].state == "running")
        expect(containers[1].ports == [5432] && containers[1].status.hasPrefix("Exited"))
        expect(Docker.publishedPorts("") == [] && Docker.publishedPorts("80/tcp") == [])
    }),
    ("the containers in ⌘K: a shell row each, and the running ones' ports to the preview", {
        let pc = Tailnet.status(Data(statusRunning.utf8))!.others.first { $0.name == "pc" }!
        let containers = [DockerContainer(name: "web", image: "node:22", state: "running", status: "Up", ports: [3000, 9000]),
                          DockerContainer(name: "db", image: "postgres", state: "exited", status: "Exited", ports: [5432])]
        let items = ContainerSource.items(containers, machine: pc, query: "")
        expect(items.map(\.title) == ["web", "web  :3000", "web  :9000", "db"], "\(items.map(\.title)): a stopped one's ports are not offered")
        expect(items[1].detail?.hasSuffix("http://pc.tail1234.ts.net:3000") == true)
        expect(ContainerSource.items(containers, machine: pc, query: "postgres").map(\.title) == ["db"])
        let shell = Docker.shellLine(context: "pc", container: "web")
        expect(shell.hasPrefix("docker --context 'pc' exec -it 'web' sh -c") && !shell.contains("context use"), shell)
    }),
]
