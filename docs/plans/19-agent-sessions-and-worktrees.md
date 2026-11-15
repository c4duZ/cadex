# Plano 19 — Sessões de agente e worktree por tarefa

Depende de: plano 18 (kit da sessão, executável `cadex`, contas) · Features: worktrees (nova,
núcleo e app), agent-tools (do plano 18), agents, terminal, tabs, spaces, sidebar, status-bar,
settings, command-palette, source-control · Decisões: ADR 0022 e ADR 0023 (a escrever na fase A),
docs/adr/0021-cadex-managed-accounts.md (do plano 18), `docs/adr/0019-agents-observe-only.md`,
`docs/adr/0002-zig-core-with-c-api.md`, `docs/adr/0003-libghostty-vt-terminal-model.md`,
`docs/adr/0004-clean-rewrite.md`, `docs/adr/0005-every-action-is-a-command.md`.

## O que eu quero
- Trazer para o Cadex o jeito do Orca de tratar sessões (o dono, 2026-11-14), nativo e leve:
  cada tarefa é uma worktree com branch e agente próprios, a sessão sobrevive ao app, e o Cadex
  sabe com exatidão o que cada agente está fazendo e o que espera de você.
- "Nova tarefa": um comando cria a worktree, o branch e abre o agente na conta certa (a do projeto
  ou a ativa, plano 18), já com os hooks de preparo rodados (`pnpm install`, `direnv allow`) e os
  arquivos fora do git copiados pelo `.worktreeinclude` (`.env` e afins).
- Status de cada worktree (a fazer, em andamento, em revisão, pronto) e um comentário curto do que
  ela está fazendo agora, que o próprio agente vai atualizar (o canal do agente é do plano 20; aqui
  o modelo e a vista).
- Fechar, travar ou atualizar o Cadex não mata os agentes: um processo à parte é dono dos
  terminais; ao abrir, o app religa e o scrollback volta. Depois de reiniciar o Mac, voltam o
  layout e o scrollback salvo, não os processos. Desligado por padrão até provar (o dono,
  2026-11-14).
- Agente que terminou e está parado há um tempo é encerrado (hibernado) e volta sozinho com
  `claude --resume <id>`, na mesma pasta e conta, quando você abre a worktree. Agente que saiu
  ganha um botão para reiniciar igual.
- Estado exato de cada sessão (trabalhando, esperando permissão, pergunta, terminou), vindo dos
  hooks do Claude Code e não do fim do log; o título da aba mostra o estado e o nome da conversa
  (fecha a pendência do plano 17).
- Atenção num lugar só: sininho com não lidos, número no ícone do Dock, marcar como não lido, um
  feed com a linha do tempo de todas as worktrees e o quadro "Precisa de você", onde se aprova ou
  nega uma permissão sem ir até o terminal.

## O que eu não quero
- Mandar prompt, chamar modelo ou embutir chat: o agente continua na aba de terminal. Responder a
  um pedido de permissão é a única fala com o agente, e só com o dono clicando (ADR 0023). Abrir o
  agente sem prompt (Nova tarefa, relançar) é o que a ADR 0021 já amplia.
- Esconder o diálogo do Claude Code: a permissão continua aberta na TUI; quem responder primeiro,
  no terminal ou no quadro, vence.
- Pular permissões por padrão, como o Orca faz com `--dangerously-skip-permissions`: continua
  desligado (agents.launchSkipPermissions, plano 17).
- Escrever no `~/.claude` do dono: hooks entram só pelo kit da sessão (plano 18). Sessão aberta
  fora do Cadex é lida, não configurada.
- Que qualquer processo da máquina mande eventos ao Cadex: o socket do app só aceita quem tem o
  token de uma sessão do Cadex.
- Um daemon pesando com o app fechado: sem agente rodando, ele sai sozinho; nenhum timer parado.
- Falar com a libghostty fora da feature `terminal` do núcleo, nem o Swift chamando detalhe
  interno do Zig: o daemon é um executável do núcleo, e o app fala com ele por socket com
  protocolo versionado.
- Código do Orca, do ccmanager ou do HAPI como referência (ADR 0004): só o comportamento descrito.
- Ação só em botão, arrastar ou menu: cada uma é um comando com id (ADR 0005).
- Por enquanto: máquinas remotas (plano 23), vários agentes na mesma tarefa e orquestração
  (plano 24), revisão do diff (plano 21), o Windows.

## Como eu quero
**Fases:**
- **A. ADRs e specs.** Nenhum código.
  - ADR 0022 (docs/adr/0022-terminal-daemon.md, a criar): os **dois sockets** do Cadex, com nome e
    caminho, em `~/Library/Application Support/Cadex/sockets/` (a criar, modo 0700):
    - terminal.sock: app ↔ daemon do terminal (fase E);
    - app.sock: tudo o que fala com o app (hooks e status line pelo `cadex`, depois a CLI e o MCP
      do plano 20), criado na fase B, com `getpeereid` e token por sessão.
    O daemon é um executável do núcleo (feature `terminal`), separado da janela, dono dos PTYs;
    processos separados não se falam pela API C, que continua sendo como o app usa o núcleo dentro
    dele. A decisão central é quem guarda o modelo da tela:
    - **Recomendado:** o daemon guarda só os PTYs e um buffer circular da saída crua de cada um
      (com limite); ao religar, o app reaplica esses bytes no modelo libghostty-vt dele. O desenho
      e o modelo ficam no app; o daemon é pequeno.
    - Alternativa: o daemon guarda o modelo e manda o estado da tela; só se a recomendada falhar no
      `make perf` ou na fidelidade.
    Também decide: iniciado pelo app e mantido pelo launchd só enquanto há sessão; sai sozinho sem
    sessão; versão do protocolo no aperto de mão; numa atualização do app o daemon velho segue com
    as sessões abertas e o novo pega as próximas; **desligado por padrão** (terminal.keepSessions);
    custo no `make perf`. Revê a frase da spec do terminal "o conteúdo antigo da tela não volta".
  - ADR 0023 (docs/adr/0023-answer-agent-permissions.md, a criar): o Cadex pode responder a um
    pedido de permissão (permitir, negar) pelo hook PermissionRequest, só por clique do dono, com o
    diálogo da TUI aberto e a primeira resposta vencendo. É a única exceção à regra dos hooks de
    nunca esperar o app (fase B). Revê "não manda prompt" da ADR 0019 nesse ponto.
  - Specs: docs/spec/worktrees.md (a criar, modelo do `docs/spec/README.md`);
    `docs/spec/agents.md` ganha Estado por hooks, Atenção, Quadro, Hibernação;
    `docs/spec/terminal.md` e `docs/spec/tabs.md` ganham sessão que sobrevive e o título com
    estado; `docs/spec/spaces.md` ganha o scrollback restaurado. Termos no `docs/CONTEXT.md`:
    Tarefa, Worktree de tarefa, Hook de preparo, Status da worktree, Daemon do terminal, Socket do
    app, Token da sessão, Hibernar, Quadro de atenção.
- **B. Socket do app e estado exato por hooks.**
  - Servidor do app.sock na parte de app da feature agent-tools (apps/macos/features/agent-tools/,
    a criar, com `CLAUDE.md`); o kit da sessão (plano 18) gera um token por sessão,
    CADEX_SESSION_TOKEN no ambiente da aba, guardado no disco (`…/Cadex/sessions/<id>.token`, a
    criar, modo 0600) para valer depois de reiniciar o app e de hibernar; o servidor confere o
    token e o dono do processo (`getpeereid`).
  - O executável `cadex` ganha `cadex hook <evento>`: lê o JSON do stdin e manda ao app.sock. O
    caminho do socket fica num arquivo relido a cada chamada, para um agente que sobreviveu ao
    reinício do app achar o app novo (comportamento do Orca). Alternativa medida em 2026-11-14:
    hook `"type":"http"` para um listener do app em 127.0.0.1 (porta aleatória, token no header)
    custa 0,3 ms por evento contra ~4 ms de abrir um processo (28 ms se fosse Python), e funciona
    (o Claude registra o 200). A ADR 0022/0023 escolhe; app fechado, os dois só falham e o Claude
    segue.
  - No kit entram hooks SessionStart, Stop, Notification (`notification_type`:
    `permission_prompt`, `idle_prompt`, `agent_needs_input`…), PermissionRequest, SessionEnd e
    CwdChanged (os hooks do `--settings` se somam aos do dono: plano 18). O hook nunca espera o
    app: sem resposta em 200 ms, sai e o Claude segue (exceção: PermissionRequest, ADR 0023).
  - **Estado pelo OSC 7501, a fonte principal em qualquer aba do Cadex** (protocolo achado no teste
    de 2026-11-14, Claude Code 2.1.325). Ao abrir, o Claude manda `ESC]7501;?BEL` (junto de
    XTVERSION, kitty e DA1); o núcleo (feature `terminal`) responde `ESC]7501;?;1 BEL` e passa a
    receber `ESC]7501;state=…:app=claude-code[:kind=…][:msg=<base64>] BEL`, pares chave=valor
    separados por ":": `state` idle, working (com `msg`, a frase do que faz: "Creating empty file…"),
    blocked (com `kind` permission ou question e `msg`: "approve Bash: touch x", "answer: Qual
    cor…? (Azul · Verde)") e done. Com a resposta, o Claude tira o sinal do título. O núcleo entrega
    ao app o estado por terminal; chave ou estado desconhecido não quebra; `msg` pode faltar.
  - Daí vêm o estado, o tipo e o texto da parada para notificações e para o quadro (fase C), sem
    hook e sem log, também para um `claude` digitado à mão numa aba. Os hooks ficam para AGIR
    (PermissionRequest, ADR 0023) e para o que o 7501 não traz (id da sessão, `transcript_path`,
    `/clear` e `--resume`, que o `sessions/<pid>.json` não acompanhava). A leitura dos 64 KB do fim
    do log (AgentStop.swift) fica só para sessões em outros terminais.
  - Título da aba: sinal de estado (trabalhando, esperando, terminou, terminou sem você ver), a
    frase do `msg` e o nome da conversa; renomear à mão continua vencendo (`docs/spec/tabs.md`).
    Fecha a pendência do plano 17.
  - Sessões em segundo plano (`claude --bg`) já estão na página Agents (feito em 2026-11-14,
    `apps/macos/features/agents/AgentBackground.swift`: `claude agents --json` só quando a pasta
    jobs/ muda, no máximo a cada 5 s; duplo clique abre `claude attach <job>`).
  - Configuração agents.stateHooks (ligada). Features: agents, agent-tools, terminal, tabs,
    settings.
- **C. Atenção e quadro "Precisa de você".**
  - Sininho no topo da barra lateral com os não lidos de todas as worktrees; número no ícone do
    Dock; "Marcar como não lido"; clicar leva ao terminal (como a notificação de hoje).
  - Feed de agentes: linha do tempo de terminou, travou numa pergunta, pediu permissão e worktree
    criada, com filtro; página da barra lateral.
  - Quadro: um cartão por pedido aberto. Permissão mostra a ferramenta e o comando ou arquivo, com
    Permitir e Negar; pergunta e plano mostram o texto e "Ir ao terminal" (responder a pergunta
    fica para depois). Testado em 2026-11-14 (2.1.325) nos dois sentidos: o diálogo "Do you want to
    proceed?" fica aberto enquanto o hook espera; o hook respondendo `allow` resolve; respondendo
    na TUI primeiro, o comando roda na hora e a resposta tardia do hook é ignorada. O hook recebe
    `tool_name`, `tool_input`, `permission_suggestions`, `session_id`, `cwd`, `transcript_path`; o
    Notification chega com `notification_type` `permission_prompt`.
  - Silenciar notificações por máquina (agents.mutedMachines; só este Mac agora, as remotas no
    plano 23).
  - Comandos: agents.show-attention, agents.approve, agents.deny, agents.mark-unread,
    agents.show-feed. Configurações agents.attention, agents.dockBadge. Features: agents, sidebar,
    status-bar, settings, command-palette.
- **D. Worktree por tarefa.** Feature nova `worktrees`: núcleo (core/features/worktrees/, a
  criar: `git worktree` pelo binário do git, como a source-control; cópia do `.worktreeinclude`;
  rodar os hooks de preparo com a saída num terminal) e app (apps/macos/features/worktrees/, a
  criar: a vista e os comandos). Pasta com `CLAUDE.md`, testes e linha na tabela do `CLAUDE.md` da
  raiz; spec da fase A antes do código.
  - "Nova tarefa" (worktrees.new-task): nome → branch derivado, ponto de partida (branch atual por
    padrão, gravado para a revisão do plano 21), pasta em worktrees.root (padrão: ao lado do
    repositório, em `<repo>.worktrees/`). Essa pasta pode cair fora dos diretórios autorizados da
    feature `workspace`: a primeira tarefa num repositório pede para autorizá-la (uma vez), e
    recusar deixa escolher outra raiz. Copia o `.worktreeinclude`; roda os hooks de preparo; abre
    o agente sem prompt na conta do projeto ou na ativa (ADR 0021).
  - Sem cópia de sessões entre worktrees (o worktrees.carrySessions saiu): testado em 2026-11-14,
    de dentro de uma worktree `claude --resume <id>` acha a conversa do repositório sem copiar nada,
    e a memória automática é uma só para o repositório e as worktrees. O Cadex retoma pelo id.
  - Confiança da pasta: numa pasta nunca aberta o diálogo "trust this folder" segura o prompt e o
    `claude --bg` sai com erro; a confiança vale para as pastas filhas, inclusive as criadas depois
    (testado em 2026-11-14). Corrigido em 2026-11-15: numa worktree a confiança que vale é a do
    repositório principal, então aceitar em `<repo>.worktrees/` não cobre as tarefas; aceitar na aba
    da primeira tarefa grava a do repositório e cobre todas, as de antes e as de depois. Sem aba a
    mais: na primeira "Nova tarefa" o Cadex explica numa folha que o dono aceita uma vez, ali. O
    Cadex não escreve no .claude.json.
  - Status e comentário: guardados pelo Cadex (não no git), mostrados na lista de worktrees e no
    título do grupo em Agents › Sessions; worktrees.set-status e worktrees.set-comment.
  - Hooks de preparo por repositório nas configurações (worktrees.setupHooks), mostrados antes da
    primeira vez que rodam.
  - Outros comandos: worktrees.open, worktrees.remove (com confirmação; mudanças não salvas
    impedem), worktrees.edit-setup-hooks. Features: worktrees, agents, source-control, tabs,
    settings, command-palette.
- **E. Daemon do terminal.** Pela ADR 0022, em duas partes, cada uma numa sessão:
  - **E1. O daemon e o protocolo.** O núcleo ganha o modo daemon (PTYs, buffer da saída crua,
    terminal.sock, aperto de mão com versão, saída sozinho sem sessão); testes do núcleo com um
    shell falso (`make core-test`, sem vazamento). O app ainda não usa. Feito em 2026-11-15
    (`cadex-terminald`; detalhes na ADR 0022): falta à E2 o launchd ("mantido pelo launchd só
    enquanto há sessão"), o empacotamento em Contents/Helpers e o app usar o daemon.
  - **E2. O app pelo daemon.** Com terminal.keepSessions ligado, o app abre e liga terminais pelo
    daemon; fechar a janela ou o app deixa as sessões lá; reabrir religa e reaplica o buffer no
    modelo (scrollback); travar o app não derruba nada. Ao reiniciar o Mac, o scrollback salvo de
    cada painel volta com o layout, e o painel abre um shell novo (sem prometer processo). Fechar
    painel com programa rodando continua pedindo confirmação.
  - Configuração terminal.keepSessions (**desligada por padrão**; desligada, o comportamento de
    hoje, sem daemon nenhum). Features: terminal, spaces, tabs, settings.
  - Junto do terminal (teste de 2026-11-14): o Claude liga saída sincronizada, kitty keyboard,
    progresso OSC 9;4 e notificação OSC 777 só para terminais que conhece pelo `TERM_PROGRAM`; o
    Cadex exporta `TERM_PROGRAM=Cadex` e não ganha nenhum. O renderizador passa a respeitar o modo
    DEC 2026 (desenhar só no fim do bloco) e só então o kit liga `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1`
    (plano 18); a notificação vem por `preferredNotifChannel`. Kitty keyboard e OSC 9;4 não voltam
    sem fingir ser outro terminal: trocar o `TERM_PROGRAM` só com ADR. Feito em 2026-11-15: o
    quadro fica parado durante o bloco (no máximo 200 ms) e o kit liga a variável pelo `env` do
    `--settings`; com ela o `claude` real mandou 10 blocos nos primeiros segundos, sem ela nenhum.
- **F. Hibernar e reiniciar.** Sessão terminada, sem foco e parada há agents.hibernateAfterMinutes
  (padrão 30; 0 desliga) é encerrada, guardando o id, a pasta, a conta, o comando e o token.
  Abrir a worktree ou a aba relança com `CLAUDE_CONFIG_DIR=<conta> claude --resume <id>` na mesma
  pasta, com o kit e o mesmo token. Agente que saiu mostra "Reiniciar" (agents.restart).
  agents.hibernate hiberna na hora. Features: agents, terminal, tabs, settings.
- **G. Peso e fechamento.** Cenários no `tools/perf/run.py`: 10 terminais pelo daemon, com e sem
  janela; 5 sessões falsas mandando hooks a cada segundo; tudo desligado igual ao de hoje. Todos
  os ids novos em `MAC_ONLY` de `tools/check_command_parity.py` (inclusive os de worktrees, até o
  Windows ganhar a vista); saem de lá com o port. `CLAUDE.md` das features tocadas, README e notas
  da release em inglês.

## Como validar
- `make check` a cada fase; `make perf` nas fases B a G (mexem em terminal, desenho e leitura em
  segundo plano): tudo desligado, os números de hoje; tudo ligado, até 10% a mais de memória e CPU
  parado sem mudança; o daemon sem sessão não aparece no `ps`.
- Fase A: as duas ADRs citam o que revêem; os dois sockets com nome e caminho; specs com
  critérios; `make manifests` passa.
- Fase B: numa aba aberta pelo Cadex, pedir um `rm` mostra "esperando permissão" em até 1 s e o
  título da aba muda; `/clear` e `--resume` mantêm o id certo; com o app fechado no meio, o próximo
  hook acha o app reaberto e o token ainda vale; com o app fechado, o Claude não espera o hook; um
  processo sem token (ou de outro usuário) é recusado no app.sock; um `claude` digitado à mão numa
  aba mostra trabalhando, permissão e pergunta (com o texto do `msg`) só pelo OSC 7501; testes do
  núcleo com as sequências gravadas no teste de 2026-11-14 e com chaves desconhecidas.
- Fase C: Permitir no quadro faz o comando rodar e fecha o diálogo da TUI; responder na TUI tira o
  cartão; o número do Dock some ao visitar; nada é mandado ao agente sem clique.
- Fase D: "Nova tarefa" num repositório com `.worktreeinclude` e um hook de preparo cria a
  worktree, copia o `.env`, roda o hook e abre o agente na conta do projeto; a pasta fora do
  workspace pede autorização; depois de aceitar a confiança uma vez na primeira tarefa, a
  segunda tarefa abre sem diálogo; remover com mudanças não salvas é recusado; testes do núcleo com
  repositório falso (`make core-test`, sem vazamento).
- Fase E: `top` rodando, fechar e reabrir o Cadex mostra o mesmo `top` com o scrollback; matar o
  app com `kill -9` não derruba o terminal; atualizar o app com uma sessão aberta a mantém viva;
  com terminal.keepSessions desligado, nenhum daemon roda.
- Fase F: depois do tempo, a sessão hibernada some do `ps`; abrir a worktree retoma a conversa
  (pedir a palavra-código, como no teste de 2026-11-14).
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`).
