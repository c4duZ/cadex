# machines (app macOS)

## O que eu quero
- As máquinas da tailnet do dono à vista e a um clique: no cartão do ssh, abaixo dos hosts do
  `~/.ssh/config`, com online, caminho (direto ou relay) e latência, e `ssh <usuário>@<máquina>`
  numa aba (plano `../../../../docs/plans/23-machines.md`, fase B; `../../../../docs/spec/machines.md`;
  `../../../../docs/adr/0030-installed-tailscale.md`).

## O que eu não quero
- Instalar, embutir ou pedir o Tailscale: sem ele, nada aparece e nada dá erro.
- Ler ou vigiar com ninguém olhando, ou com machines.tailscale desligado (nem arquivo, nem socket,
  nem processo do Tailscale).
- Mudar a configuração do Tailscale; ler chave ssh, senha ou tráfego.
- O ssh importando esta feature: o app põe o grupo no cartão dele.

## Como eu quero
- `Tailnet.swift`: puro e testado. Os tipos (`Machine`, `MachinePath`, `TailnetStatus`,
  `MachinePing`) e a leitura tolerante do status (campo que falta é pulado e marca a leitura como
  parcial; JSON quebrado é nil), do ping da LocalAPI e do `tailscale ping` da CLI, e
  `busLineMatters`: no fluxo de mudanças, só os contadores do motor (um a cada 2 s, medido em
  2026-11-16) não contam, a não ser que o número de pares vivos mude.
- `TailscaleDaemon.swift`: acha o daemon na ordem da ADR 0030: o socket do `tailscaled`, o app
  Standalone (o link `ipnport` e o `sameuserproof-<porta>` em /Library/Tailscale), o app da App
  Store (só lista os nomes do Group Containers; entra só no dele, `sameuserproof-<porta>-<token>`,
  formato não conferido num App Store de verdade) e a CLI (com o binário do app,
  `TAILSCALE_BE_CLI=1`). Os caminhos são campos, para os testes.
- `LocalAPI.swift`: HTTP/1.0 cru pelo socket Unix ou por 127.0.0.1 (o servidor do Tailscale responde
  sem chunked e o fluxo vem em linhas; conferido com curl em 2026-11-16), com
  `Sec-Tailscale: localapi` e a prova como senha Basic; 3 s de prazo; a CLI com prazo também.
  `WatchHandle` encerra o fluxo que bloqueia num `read` de outra thread.
- `MachinesController.swift`: a porta de entrada, uma para o app (`shared`). `watch`/`stop` (o
  cartão aberto): lê, mede a latência de cada máquina online uma vez (o ping da LocalAPI, sem
  processo), segue o `watch-ipn-bus` relendo o status a cada mudança e, se o fluxo não começar ou
  cair, relê a cada 30 s; `refresh` (a paleta lê uma vez); `ping`; `isEnabled` (machines.tailscale)
  desligado para e esquece tudo. Leitura, ping e fluxo são campos, para os testes.
- `MachinesSection.swift`: o grupo "Tailnet 2/3" que o app põe no cartão do ssh (`extraContent` do
  `SSHStrip`): a bolinha (verde direto, amarela relay, vermelha offline, cinza antes do ping), nome,
  sistema, endereço e a resposta; estados sem login, sozinho na tailnet e leitura parcial.
- `MachinesCommands.swift`: machines.connect (⌥↩ pergunta o usuário de novo), machines.ping (a
  paleta reabre com a resposta), machines.refresh, machines.copy-address (⌥↩ copia o IP).
- Docker pela tailnet (fase D, `../../../../docs/adr/0032-workspace-recipes.md`): `Docker.swift` (o
  `docker` do dono, nunca um cliente próprio: o contexto `<máquina>` com `host=ssh://`, criado se
  faltar; nunca `docker context use`; a leitura do `docker context ls` e do `docker ps --all` em
  JSON, as portas publicadas na máquina; a linha do `export DOCKER_CONTEXT` e do `docker exec`) e
  `DockerCommands.swift` (machines.docker-context, com "Este Mac" primeiro, e machines.docker-ps:
  as máquinas e depois os contêineres no ⌘K, um shell por contêiner e as portas dos que rodam).
  `isMachine`: se um nome (curto, MagicDNS ou 100.x) é de uma máquina da tailnet, para a oferta do
  preview; lê uma vez se ninguém leu, e quem pergunta junto espera a mesma leitura.
- Aceitar outras máquinas (fase F): `TailnetListener.swift`, TCP na porta 47100 preso ao IP 100.x
  deste Mac (nunca a todas as interfaces, só IPv4), ligado por machines.acceptRemote (desligada) e
  pelo controller quando a leitura dá o endereço e o dono deste Mac (`applyListener`); cada conexão
  passa pelo WhoIs da LocalAPI e só o aparelho do mesmo dono vai a `onAccepted` (o app entrega ao
  servidor do app.sock); o resto é fechado sem resposta.
- Compartilhar um servidor deste Mac (fase G): `TailscaleServe.swift` (puro: as portas que o
  `tailscale serve status --json` já usa, a primeira livre de 443, 8443 e 10000, os argumentos de
  `serve`/`funnel --bg --yes --https=<porta>` e de `--https=<porta> off`, o endereço, a permissão do
  Funnel no Self do status, a porta de uma página local; e `TailnetShares`, o que o Cadex ligou, no
  shares.json dele), `MachinesShare.swift` (`share` e `stopSharing` pelo CLI do dono, nunca
  `serve reset`, nunca a porta que o dono serve) e `ShareCommands.swift` (machines.share-port,
  machines.share-public, que o app confirma, e machines.stop-sharing com a lista no ⌘K).
- O app (`../../app/MachinesWiring.swift`) liga o grupo ao cartão do ssh, lê só com o cartão aberto
  (`onCardOpen`, pelo `onOpenChange` do `HoverCard`) e abre a aba com `ssh '<usuário>@<máquina>'`;
  o usuário é pedido uma vez por máquina e guardado em machines.users.
- Status: fases B (cartão do ssh) e D (Docker, a oferta do preview) no código (2026-11-16).

## Como validar
- `make macos-test` (`tests/main.swift`, respostas gravadas em `tests/Fixtures.swift`, uma LocalAPI
  falsa em `tests/FakeDaemon.swift`): status completo, versão velha, JSON quebrado, sem login,
  sozinho; pings; o fluxo de mudanças; compartilhar com um CLI falso (`tests/ShareTests.swift`, nunca o
  `serve` de verdade); o listener com WhoIs falso (`tests/ListenerTests.swift`); o Docker (`tests/DockerTests.swift`); um nome ser máquina; a ordem da detecção; a prova e o cabeçalho no pedido, 401;
  nada lido sem ninguém olhando, o fluxo parando ao fechar, os 30 s quando o fluxo falha, desligado.
- Na mão, com o Tailscale do dono: o cartão do ssh mostra o grupo em até 2 s, igual ao
  `tailscale status`; com o PC na tailnet, desligá-lo o marca offline.
