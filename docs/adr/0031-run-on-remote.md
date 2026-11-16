# 0031 — "Rodar em" outra máquina: o mínimo por ssh, o completo com um núcleo sem janela

Data: 2026-11-16 · Status: aceita (o mínimo); o completo, decidido para depois do mínimo em uso ·
Revê, só no completo, o escopo de plataformas de `docs/adr/0001-macos-first-native-app.md` ("Linux
fora do escopo") e de `docs/adr/0012-windows-zig-win32-d3d11.md`, e o "só a própria máquina" dos
sockets de `docs/adr/0022-terminal-daemon.md` · Apoia-se em `docs/adr/0030-installed-tailscale.md`
· Plano `docs/plans/23-machines.md`

## Contexto
O dono quer criar uma tarefa (plano 19: worktree, branch e agente) e mandar ela rodar no PC de
mesa, que tem mais núcleos, mais memória e o Docker, enquanto lê e revisa daqui. O PC é Windows; o
caminho é o Ubuntu do WSL com o Tailscale dentro dele, uma máquina Linux comum na tailnet, com
`sshd`, `git`, `docker` e `claude` (o dono, 2026-11-14).

Hoje tudo o que o Cadex sabe de uma tarefa vem desta máquina: a worktree no disco, o terminal no
daemon (ADR 0022), os hooks e o `cadex` das sessões (ADR 0024), o diff do git. Numa máquina remota
nada disso existe, a não ser que algo do Cadex rode lá.

O comportamento de referência é o "Run on" do Orca: a worktree e o agente ficam no remoto, a
janela fica aqui. Sem código dele (ADR 0004).

## Decisão
- **Dois degraus, nesta ordem.** Primeiro o **mínimo**, que não instala nada no remoto; o
  **completo** só depois que o mínimo estiver em uso de verdade.
- **Mínimo (plano 23, fase C):** "Rodar em" no "Nova tarefa" escolhe este Mac, um host do
  `~/.ssh/config` ou uma máquina da tailnet. No remoto, uma aba de terminal com `ssh` roda os passos
  da tarefa lá (achar ou clonar o repositório, `git worktree add`, os hooks de preparo) e abre
  `claude` na pasta remota, com o login do Claude **do remoto** (o Cadex não leva conta, chave nem
  sessão daqui para lá).
  - A sessão remota **não tem kit, hooks nem `cadex`**: o Cadex não sabe o estado dela pelos hooks.
    Sabe pelo `claude agents --json` rodado por ssh, só com a página Agents aberta, e mostra a
    sessão como "em <máquina>".
  - Fechar a aba não apaga nada no remoto. Diff, editor e revisão do que está no remoto ficam para
    o completo.
  - Comandos worktrees.new-task-on e worktrees.open-remote-shell.
- **Completo (depois, com plano próprio):** o `cadexd`, o núcleo Zig sem janela compilado para
  Linux, com o daemon do terminal do plano 19 servindo as sessões de lá; o Cadex do Mac é o
  cliente, pela tailnet, e só aceita (e só é aceito) por WhoIs, aparelhos do mesmo usuário
  (ADR 0030). Com ele vêm o kit, os hooks, o diff e o editor remotos.
  - É um alvo de build novo (`zig build` para Linux) e um núcleo sem janela: o Linux entra no
    escopo **só como servidor**, nunca como app com interface (a ADR 0001 segue valendo para a
    interface).
  - O daemon passa a atender outra máquina, o que hoje a ADR 0022 não faz (os dois sockets são
    Unix, desta máquina). A porta para isso nasce na fase F do plano 23: um listener TCP preso só
    ao IP 100.x da tailnet, nunca em 0.0.0.0, desligado por padrão (machines.acceptRemote), com
    WhoIs em cada conexão e o mesmo protocolo do socket.

## Alternativas recusadas
- **Começar pelo completo:** muito código (um núcleo para Linux, um protocolo de rede, um daemon
  remoto) antes de saber se o dono usa o "Rodar em" de verdade.
- **Montar a pasta remota aqui (sshfs, SMB, NFS):** o git e o agente rodariam aqui sobre um disco
  lento, e o ponto é rodar lá.
- **Levar a conta do Claude daqui para o remoto:** copia credencial entre máquinas; o remoto usa o
  login dele.
- **Um agente do Cadex em Node, Python ou outra linguagem no remoto:** outra pilha para manter; o
  núcleo já é Zig e já tem o daemon.
- **Abrir o daemon em 0.0.0.0 ou com token próprio:** expõe o terminal à rede local; a tailnet com
  WhoIs já diz quem é quem.

## Consequências
- `docs/spec/worktrees.md` ganha "Rodar em"; `docs/spec/agents.md`, a sessão "em <máquina>";
  `docs/spec/machines.md`, o listener da tailnet.
- No mínimo, uma sessão remota tem menos que uma local (sem estado por hook, sem diff, sem revisão)
  e a spec diz isso.
- O completo, quando vier, precisa de plano e de uma ADR que diga o protocolo e o build para Linux.
- Propor um app com interface no Linux, abrir o daemon fora da tailnet ou levar credencial entre
  máquinas é desfazer esta decisão.
