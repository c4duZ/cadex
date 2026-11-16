# Plano 23 — Várias máquinas pelo Tailscale

Depende de: planos 19 e 20 (worktree por tarefa, daemon, socket e CLI `cadex`) · Features: machines
(nova, app macOS), ssh, worktrees, preview, agents, status-bar, settings, command-palette ·
Decisões: `docs/adr/0030-installed-tailscale.md`, `docs/adr/0031-run-on-remote.md`,
`docs/adr/0032-workspace-recipes.md` (escritas na fase A), `docs/adr/0004-clean-rewrite.md`,
`docs/adr/0005-every-action-is-a-command.md`, `docs/adr/0007-one-step-install.md`,
`docs/adr/0001-macos-first-native-app.md`, `docs/adr/0012-windows-zig-win32-d3d11.md`,
docs/adr/0022-terminal-daemon.md (do plano 19), docs/adr/0024-agent-tools.md (do plano 20).

## O que eu quero
- Usar as outras máquinas do dono como se fossem este Mac (o dono, 2026-11-14: "ligando o meu PC
  de mesa, ligando um Docker lá com uma máquina Ubuntu, usando e subindo as coisas por lá").
- O Tailscale que o dono já instalou é a rede: cada máquina tem um nome (`pc.<tailnet>.ts.net`),
  o tráfego vai cifrado direto entre elas quando dá, e o Cadex sabe quem está do outro lado de uma
  conexão (WhoIs) sem token próprio.
- Na feature ssh, as máquinas da tailnet ao lado do `~/.ssh/config`: nome, sistema, online, última
  vez visto, caminho direto ou por relay, latência; um clique abre `ssh <user>@<host>` numa aba.
- "Rodar em" ao criar uma tarefa (plano 19): este Mac ou uma máquina remota. No remoto ficam o git,
  a worktree e o agente; aqui ficam o editor, o diff e a janela (o "Run on" do Orca).
- Docker do PC mandado daqui: o `docker` do Mac aponta para o daemon do PC pela tailnet; um
  contêiner Ubuntu com o Tailscale ao lado aparece como mais uma máquina; o preview abre os
  serviços dele pelo nome (`http://ubuntu-dev:3000`).
- O PC de mesa do dono é Windows (o dono, 2026-11-14). O caminho é o Ubuntu do WSL com o
  Tailscale instalado **dentro dele**: o WSL vira uma máquina Linux comum na tailnet (nome
  próprio, ssh direto, `docker` e `claude` rodando lá), sem servidor OpenSSH no Windows. O Docker
  Desktop, se usado, já roda no WSL e responde ao `docker` desse Ubuntu.
- Ambiente descartável por worktree: um contêiner (ou VM) criado a partir de uma receita no
  repositório, que se suspende, retoma e destrói junto com a tarefa.
- Mostrar um servidor local do Mac na tailnet (`tailscale serve`), para abrir no celular; para a
  internet (Funnel) só com confirmação.
- Notificações silenciáveis por máquina (pendência do plano 19).

## O que eu não quero
- Exigir o Tailscale: sem ele, nada desta fase aparece e nada dá erro (ADR 0007). Nenhuma tela pede
  para instalar.
- Embutir a libtailscale: cerca de 20 MB a mais (medido em 2026-11-14), runtime Go dentro do app e
  um panic do Go derruba o Cadex. Fica registrado como opção futura na ADR 0030.
- Uma tailnet do Cadex para os usuários, ou a marca Tailscale como nossa: os termos deles são de
  uso pessoal ou interno (https://tailscale.com/terms).
- Guardar chave do Tailscale ou do Docker: a chave de autenticação de um contêiner é colada pelo
  dono na receita ou no ambiente dele, nunca salva pelo Cadex.
- Mudar a configuração do Tailscale do dono sem um comando explícito: `serve` e `funnel` só por
  comando, e o Cadex desfaz o que ele mesmo ligou.
- Ler tráfego, chave SSH ou senha: o Cadex lê a lista de máquinas e pergunta quem é quem.
- Testar ou vigiar com ninguém olhando, ou com machines.tailscale desligado.
- Por enquanto: o celular (depois do motor), o Windows (LocalAPI por named pipe, com o port) e o
  Taildrop (alfa, cai no `~/Downloads`).

## Como eu quero
**Fases:**
- **A. ADRs, spec e termos.**
  - ADR 0030 (`docs/adr/0030-installed-tailscale.md`): o Cadex usa o Tailscale instalado.
    Acha o daemon nesta ordem: socket do `tailscaled` aberto (/var/run/tailscaled.socket), app
    Standalone (porta e token em arquivos sob /Library/Tailscale/), app da App Store (arquivo no
    Group Container, que faz o macOS pedir permissão uma vez) e, sem nenhum, a CLI
    (`tailscale status --json`, ou o binário de dentro do app com `TAILSCALE_BE_CLI=1`). A LocalAPI
    não promete estabilidade: campo que falta é pulado, nada trava, a página diz o que não leu.
    Identidade entre máquinas por WhoIs (só aparelhos do mesmo usuário). libtailscale recusada,
    com os números.
  - ADR 0031 (`docs/adr/0031-run-on-remote.md`): "Rodar em" uma máquina remota. Mínimo:
    aba ssh que cria a worktree e abre `claude` na pasta remota (o login do Claude fica no remoto).
    Completo: `cadexd`, o núcleo Zig sem janela num Linux, com o daemon do plano 19 (ADR 0022)
    servindo as sessões de lá e o Cadex do Mac como cliente pela tailnet, aceito só por WhoIs. O
    completo é alvo novo de build (`zig build` para Linux, um núcleo sem janela), o que revê o
    escopo de plataformas das ADRs 0001 e 0012 (macOS e Windows), e entra só depois do mínimo em
    uso. Sessão remota no mínimo não tem kit, hooks nem `cadex`: só o estado lido por
    `claude agents --json` via ssh.
  - ADR 0032 (`docs/adr/0032-workspace-recipes.md`): receita de ambiente por repositório
    (.cadex/environment.toml, a criar em cada repo que usar): imagem ou Dockerfile, máquina onde
    roda, portas, comando de preparo, sidecar do Tailscale (nome, `TS_AUTHKEY` lido do ambiente do
    dono). O Cadex roda `docker` (local ou por contexto remoto); não fala com nuvem nenhuma nesta
    fase. Comportamento das receitas do Orca (orca.yaml), sem código dele (ADR 0004).
  - `docs/spec/machines.md`; `docs/spec/ssh.md`, `docs/spec/worktrees.md` (do plano 19),
    `docs/spec/preview.md` e `docs/spec/agents.md` atualizadas; termos Tailnet, Máquina, Rodar em,
    Contexto Docker, Receita de ambiente e Ambiente descartável no `docs/CONTEXT.md`.
  - Feita em 2026-11-16: `docs/adr/0030-installed-tailscale.md`, `docs/adr/0031-run-on-remote.md`,
    `docs/adr/0032-workspace-recipes.md` e `docs/spec/machines.md`; `docs/spec/ssh.md`,
    `docs/spec/worktrees.md`, `docs/spec/preview.md` e `docs/spec/agents.md` atualizadas; os termos
    numa seção "Máquinas" do `docs/CONTEXT.md`; as ADRs 0001, 0007, 0012 e 0022 dizem no cabeçalho o
    que foi revisto. A detecção da ADR 0030 conferida neste Mac (Tailscale 1.104.7, Standalone): sem
    /var/run/tailscaled.socket; a porta no link /Library/Tailscale/ipnport, o token em
    sameuserproof-<porta> (0640, root:admin); status, whois e watch-ipn-bus respondem com o token
    e dão 401 sem ele; o grupo compartilhado do app fechado sem permissão; /usr/local/bin/tailscale
    é um script que chama o binário do app. A tailnet do dono tinha só este Mac: as fases B a D
    precisam do PC (o Ubuntu do WSL com o Tailscale dentro) na tailnet.
- **B. Máquinas na barra lateral e no ssh.** Feature nova `machines` (só app macOS,
  apps/macos/features/machines/, a criar, com `CLAUDE.md`, testes e linha na tabela da raiz):
  - `TailscaleLocal`: acha o daemon (ADR 0030), lê o status (pares, nome MagicDNS, IP 100.x,
    sistema, dono, online, última vez visto, caminho direto ou relay) e vigia mudanças pelo
    `WatchIPNBus` (ou lê a cada 30 s com alguém olhando, se o vigia falhar). Puro e testado com
    respostas gravadas (versão velha, campo faltando, JSON quebrado, sem daemon).
  - O app (`apps/macos/app/SSHWiring.swift`) põe as máquinas no cartão do ssh, num grupo "Tailnet"
    abaixo dos hosts do `~/.ssh/config`; o ssh não importa machines. Latência por `tailscale ping`
    só ao abrir o cartão e no "Test Again".
  - Comandos: machines.connect (lista no ⌘K: aba com `ssh <user>@<host>.<tailnet>.ts.net`; usuário
    lembrado por máquina), machines.ping, machines.refresh, machines.copy-address.
  - Configuração machines.tailscale (ligada; sem daemon, nada aparece). Desligada: nenhum socket
    aberto, nenhum processo rodado.
  - No código em 2026-11-16 (`apps/macos/features/machines/CLAUDE.md`): a feature lê o Tailscale só
    com o cartão do ssh aberto (o `HoverCard` ganhou `onOpenChange`) ou com a paleta listando as
    máquinas; a latência vem do ping da LocalAPI (sem processo; a CLI só sem LocalAPI). Achado ao
    conferir a LocalAPI: o `watch-ipn-bus` sem bits manda os contadores do motor a cada 2 s, e o bit
    do netmap inicial agora é recusado ("no longer supported"); por isso o fluxo só fica aberto com
    o cartão aberto e só uma mudança que não é dos contadores (ou do número de pares vivos) relê o
    status. Testado: 15 testes com respostas gravadas e uma LocalAPI falsa, e, com
    `CADEX_MACHINES_REAL=1`, contra o Tailscale deste Mac (achou o Standalone, leu o status sem
    leitura parcial, o ping respondeu, o fluxo mandou linhas e parou quando pedido); o grupo
    desenhado num PNG (`CADEX_SNAPSHOT_DIR`). `make perf`: o app parado com 87 MB e 0,3 % de CPU,
    igual ao de antes; quatro cenários antigos (temas, abas, subagente, preview do agente) passaram
    do limite com a máquina em load 9–12 e passaram rodados de novo, isolados. **Falta** o que pede
    o PC na tailnet: as máquinas no cartão iguais ao `tailscale status`, o PC desligado virando
    offline, a aba do ssh conectando de verdade; e o cartão aberto no app clicado pelo dono.
- **C. Rodar em (mínimo).** Na feature worktrees (plano 19): o "Nova tarefa" ganha "Rodar em"
  (este Mac, um host do `~/.ssh/config` ou uma máquina da tailnet). No remoto, uma aba ssh roda os
  passos da tarefa (clonar ou achar o repo, `git worktree add`, hooks de preparo) e abre `claude`
  com a conta do remoto. A worktree remota aparece na lista com o nome da máquina; a sessão aparece
  em Agents como "em <máquina>" (lida pelo `claude agents --json` via ssh, só com Agents aberto).
  Diff e editor remotos ficam para o completo. Comandos worktrees.new-task-on e
  worktrees.open-remote-shell.
  - No código em 2026-11-16: o script do remoto (`apps/macos/features/worktrees/RemoteTaskScript.swift`)
    roda por `ssh -o BatchMode=yes` em segundo plano e devolve a pasta e o branch finais, então a
    tarefa só entra na lista quando a worktree existe lá; o ssh que pede senha ou confiança vira
    "conecte uma vez numa aba". A pasta do repositório em cada máquina é perguntada uma vez; sem
    repositório, clonar do origin só com sim. A aba roda os hooks e o `claude` por um shell de login
    (o PATH de lá). Em Agents, a leitura remota liga só com a página na tela (o notifier vigia o
    controller sempre: vigiado não é olhado). Testado com um ssh falso que roda o comando nesta
    máquina, em repositórios de verdade (worktree feita, nome único, clone, remoção recusada com
    mudança, a aba com hooks e claude) e o parse das sessões remotas. **Falta**, com o PC: o ssh de
    verdade, o `claude agents --json` de uma sessão interativa de lá (o formato das interativas foi
    lido com tolerância, nunca visto), e as notificações por máquina (fase F).
- **D. Docker pela tailnet.**
  - machines.docker-context: cria um contexto (`docker context create <máquina> --docker
    "host=ssh://<user>@<máquina>"`) e o escolhe **por aba**, com `DOCKER_CONTEXT` no ambiente dela
    (nunca `docker context use`, que mudaria o contexto global do dono); o da aba com foco aparece
    na barra de status. O Cadex só roda o
    binário `docker` que o dono já tem; sem ele, os comandos dizem isso e param. No PC Windows do
    dono, a máquina do contexto é o Ubuntu do WSL com o Tailscale dentro (não o Windows): a fase
    começa por um passo a passo testado nele (Tailscale no WSL, `sshd` no Ubuntu, usuário no
    grupo `docker`), escrito na spec.
  - machines.docker-ps: os contêineres da máquina no cartão dela (nome, imagem, portas, estado),
    com abrir shell (`docker exec -it … bash` numa aba) e abrir porta no preview.
  - Contêiner com sidecar do Tailscale: aparece como máquina própria (o nome dado na receita), e o
    preview abre `http://<nome>:<porta>` direto. A oferta "Abrir no preview" do terminal (spec do
    preview) passa a reconhecer nomes MagicDNS além do localhost.
  - No código em 2026-11-16: o terminal não tem ambiente por aba (cada shell herda o do app), então
    machines.docker-context digita `export DOCKER_CONTEXT='<máquina>'` no shell da aba com foco
    quando ele está no prompt, ou numa aba nova; o item Docker da barra de status segue a aba com
    foco. machines.docker-ps ficou no ⌘K (máquina, depois contêineres: o shell e as portas no
    preview), porque não existe um "cartão da máquina". O núcleo reporta também `http://<nome>:<porta>`
    de um nome que pode ser da tailnet (uma parte só, `*.ts.net`, 100.64/10, só com `http://`), e o
    app só oferece o de uma máquina que conhece (`isMachine`, uma leitura se preciso). O passo a passo
    do WSL está na spec, **não testado**. Testado: o detector no núcleo, a leitura do `docker context
    ls` (chaves lidas neste Mac) e do `docker ps`, as portas, a lista no ⌘K, o `export` passando pelo
    sh. **Falta**, com o PC: o contexto de verdade pelo ssh, `docker ps` de lá, um contêiner com
    sidecar virando máquina, e a oferta do preview com o nome dele.
- **E. Ambiente descartável por worktree.** Pela ADR 0032: "Nova tarefa" com receita cria o
  contêiner na máquina escolhida, roda o preparo e abre o agente dentro dele; suspender
  (`docker pause`/`stop`), retomar e destruir seguem a worktree (hibernar do plano 19 suspende;
  apagar a worktree destrói, com confirmação). Comandos worktrees.environment-up,
  worktrees.environment-suspend, worktrees.environment-resume, worktrees.environment-destroy. VM
  (Fly, Modal e outros) fica fora desta fase.
  - No código em 2026-11-16: o leitor de TOML é do Cadex e só do que a receita usa (sem
    dependência). Subir é digitado numa aba, então a chave do sidecar vem do shell do dono pelo
    ambiente (`TS_AUTHKEY="$VAR" docker run -e TS_AUTHKEY`), nunca nos argumentos nem no Cadex. O
    contêiner fica onde a worktree está; o sidecar leva as portas e o contêiner usa a rede dele. O
    agente dentro do contêiner não tem hooks e não hiberna: hibernar um agente do Mac na pasta da
    tarefa suspende, relançar ou abrir a tarefa retoma. Testado com um docker falso que anota as
    chamadas (a chave não aparece em nenhum argumento; sem ela nada sobe). **Falta** o docker de
    verdade: subir, suspender e retomar com os arquivos, destruir; o sidecar entrando na tailnet.
- **F. Identidade e notificações por máquina.**
  - O app.sock (ADR 0022, estendido pela 0024) é Unix e só serve à própria máquina. Para outras máquinas
    nasce um listener TCP preso só ao IP 100.x da tailnet (nunca 0.0.0.0), aberto só com
    machines.acceptRemote ligada (desligada por padrão); cada conexão passa por WhoIs (só aparelhos
    do mesmo usuário) e fala o mesmo protocolo do socket. Base para o `cadexd` e para o celular,
    que vêm depois.
  - Silenciar por máquina: agents.mutedMachines (plano 19) passa a listar cada host ssh e cada
    máquina da tailnet, além deste Mac.
  - No código em 2026-11-16: a porta é 47100, só IPv4 no 100.x deste Mac; o listener só existe com
    machines.acceptRemote e machines.tailscale ligadas e o endereço lido (ligar o aceite lê o
    Tailscale uma vez). O WhoIs compara o UserProfile.ID com o dono deste Mac. A conexão aceita vai
    ao servidor do app.sock (`serveRemote`): token de sessão sim, pedido do kit nunca. O silêncio
    passou a ser conferido por sessão (antes "local" desligava todos os tipos de notificação), com
    agents.mute-machine no ⌘K. Testado: o listener em 127.0.0.1 com WhoIs falso (o mesmo dono passa,
    o outro é fechado, parado nada ouve), o controller ligando e desligando, o servidor de longe.
    **Falta**, com o PC: uma conexão de verdade de lá, outro usuário recusado, e o `lsof -i` mostrando
    só o 100.x.
- **G. Compartilhar o preview.** Na feature machines (o Tailscale é dela), ligada ao preview pelo
  app (o preview não importa machines): machines.share-port roda `tailscale serve --bg <porta>`
  para a porta da aba de preview e mostra o `https://<host>.<tailnet>.ts.net` (copiar, abrir);
  machines.stop-sharing desfaz só o que o Cadex ligou. machines.share-public (Funnel, beta, portas
  443/8443/10000) pede confirmação dizendo que a porta fica aberta para a internet, e só aparece se
  o daemon aceitar. Os botões aparecem na barra do preview.
  - No código em 2026-11-16: o Cadex lê o `tailscale serve status --json` antes e usa a primeira de
    443, 8443 e 10000 livre, nunca a do dono; o que ele ligou fica no shares.json dele, e parar roda
    `--https=<porta> off` só nessa (nunca `serve reset`). O Funnel só aparece com a permissão no Self
    do status (o `CapMap` deste Mac veio vazio: aqui ele fica indisponível) e pede confirmação. O
    botão na barra do preview vem do app (`extraBarItems`) e roda o comando pelo id. Testado com um
    CLI falso; o `serve` de verdade nunca rodou (mudaria o Tailscale do dono). **Falta**, com o dono:
    o link abrindo no celular, "Stop Sharing" deixando o `serve status` vazio, e o `--https=<porta>
    off` conferido na versão dele do CLI.
- **H. Peso e fechamento.** Cenário no `tools/perf/run.py`: machines ligado com um daemon falso
  (respostas gravadas) e 20 máquinas, cartão aberto e fechado; limite de 3% acima do app parado e
  CPU parado sem mudança. Com machines.tailscale desligado, `fs_usage` e `nettop` não mostram o
  Cadex tocando no socket do Tailscale. Os ids novos em `MAC_ONLY` de
  `tools/check_command_parity.py`. README com a tailnet no ssh e o "Rodar em". Notas da release em
  inglês.

## Como validar
- `make check` passa a cada fase; `make perf` nas fases B e H.
- Fase A: as ADRs citam o que revêem (0007: o Tailscale é opcional; 0022: o daemon atende remoto
  só no completo) e os números da libtailscale; termos no `docs/CONTEXT.md`.
- Fase B: com o Tailscale do dono, as máquinas aparecem no cartão do ssh em até 2 s, com online e
  caminho iguais ao `tailscale status`; desligar o PC o marca offline; sem Tailscale (daemon
  parado), o grupo some sem erro; testes com respostas gravadas das três variantes do Mac e da CLI.
- Fase C: "Nova tarefa" em "Rodar em: pc" cria a worktree no PC e abre `claude` lá numa aba; a
  sessão aparece em Agents como "em pc"; fechar a aba não apaga a worktree remota.
- Fase D: com o contexto do Ubuntu do WSL do PC ativo, `docker ps` numa aba do Mac lista os
  contêineres do PC; um
  contêiner Ubuntu com sidecar aparece como máquina em até 30 s; `npm run dev` dentro dele faz a
  oferta "Abrir no preview" com o nome dele, e o preview abre a página.
- Fase E: uma receita de teste sobe o contêiner, o agente roda dentro dele, suspender e retomar
  preservam os arquivos, destruir remove o contêiner e pede confirmação.
- Fase F: uma conexão de outro usuário da tailnet é recusada (WhoIs); com machines.acceptRemote
  desligada, nada escuta na tailnet (`lsof -i`); ligada, só no IP 100.x, nunca em 0.0.0.0; notificações de uma máquina silenciada não
  aparecem.
- Fase G: o link ts.net abre a página no celular do dono pela tailnet; "Parar" remove o serve
  (`tailscale serve status` vazio); o Funnel só liga depois da confirmação.
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`), com o PC de mesa do dono na tailnet.
