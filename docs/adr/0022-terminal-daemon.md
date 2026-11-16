# 0022 — Daemon do terminal e os dois sockets do Cadex

Data: 2026-11-14 · Status: aceita, revista em parte por `docs/adr/0028-project-memory.md` (um
terceiro socket, o da memória) · Revê "o conteúdo antigo da tela não volta" de
`docs/spec/terminal.md` e `docs/spec/spaces.md` (com terminal.keepSessions ligado)

## Contexto
O dono quer que fechar, travar ou atualizar o Cadex não mate os agentes, como no Orca, e que o
Cadex saiba com exatidão o que cada agente faz e espera (`docs/plans/19-agent-sessions-and-worktrees.md`,
pedido de 2026-11-14). Hoje cada PTY é filho do app: o app sai, o shell e o agente saem junto. E o
estado de uma sessão vem do `sessions/<pid>.json` do Claude Code e do fim do log, lido numa parada.

Duas coisas precisam falar com o app de fora dele: os processos das sessões (hooks e status line,
pelo programa `cadex` do plano 18; depois a CLI e o MCP do plano 20) e, com as sessões mantidas,
o dono dos terminais. Medido em 2026-11-14 (Claude Code 2.1.325): um hook por processo custa ~4 ms
por evento, um hook `"type":"http"` para 127.0.0.1 custa 0,3 ms; o Claude registra a resposta dos
dois e segue quando o outro lado não responde. E o OSC 7501 dá o estado de uma sessão numa aba do
Cadex sem hook nenhum: o Claude pergunta `ESC]7501;?BEL`, o terminal responde `ESC]7501;?;1 BEL` e
passa a receber `state=idle|working|blocked|done`, `kind=permission|question` e o texto em base64.

## Decisão
- **Dois sockets Unix**, em `~/Library/Application Support/Cadex/sockets/` (pasta 0700):
  - **`app.sock`**: tudo o que fala com o app. Criado pelo app ao abrir (plano 19, fase B). Quem
    conecta mostra o token da sessão (CADEX_SESSION_TOKEN, gerado pelo kit da sessão por sessão e
    guardado em `…/Cadex/sessions/<id>.token`, 0600, para valer depois de reiniciar o app e de
    hibernar), e o app confere com `getpeereid` que o processo é do mesmo usuário. Sem token válido,
    a conexão fecha sem resposta.
  - **`terminal.sock`**: app ↔ daemon do terminal (fase E). Só o app conecta.
  - O caminho é fixo: uma sessão que sobreviveu ao app reiniciar acha o app novo no mesmo lugar.
- **Os hooks vão por `cadex hook <evento>`**, um processo por evento, para o `app.sock`, e não por
  hook `http`. A porta de um listener muda a cada abertura do app e fica escrita no `--settings` da
  sessão quando ela abre: uma sessão mantida pelo daemon mandaria para uma porta morta depois de o
  app reiniciar. Os 4 ms por evento não pesam (um evento por turno, não por tecla). O hook nunca
  espera o app: sem resposta em 200 ms, sai e o Claude segue; a única exceção é a resposta de
  permissão (`docs/adr/0023-answer-agent-permissions.md`). App fechado, o hook só falha.
- **O estado vem primeiro do OSC 7501**, que a feature `terminal` do núcleo responde e entrega ao
  app por terminal (vale também para um `claude` digitado à mão). Os hooks ficam para agir e para o
  que o 7501 não traz (o id da sessão, `transcript_path`, `/clear`, `--resume`). O fim do log só
  para sessões em outros terminais.
- **O daemon do terminal é um executável do núcleo** (feature `terminal`), separado da janela, dono
  dos PTYs. Ele guarda **só os PTYs e um buffer circular da saída crua** de cada um, com limite; ao
  religar, o app reaplica esses bytes no modelo libghostty-vt dele. O modelo da tela e o desenho
  ficam no app, e o daemon é pequeno. A API C continua sendo como o app usa o núcleo dentro dele;
  processos separados se falam pelo socket, com a versão do protocolo no aperto de mão.
- **Vida do daemon:** iniciado pelo app, mantido pelo launchd só enquanto há sessão; sem sessão,
  sai sozinho, sem timer parado. Numa atualização do app, o daemon velho segue com as sessões que
  tinha e o novo pega as próximas. Depois de reiniciar o Mac, voltam o layout e o scrollback salvo
  de cada painel, num shell novo: processo não volta.
- **Desligado por padrão** (terminal.keepSessions, o dono em 2026-11-14): desligado, nenhum daemon
  roda e o terminal é o de hoje. Liga só depois de passar no `make perf`.
- **`TERM_PROGRAM` continua `Cadex`.** O renderizador passa a respeitar o modo DEC 2026 e só então
  o kit liga `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1`; a notificação vem por `preferredNotifChannel` (revisto pelo dono em 2026-11-15: o terminal mostra
  as notificações OSC 777 e OSC 9 de qualquer programa, e o kit deixa o `preferredNotifChannel`
  desligado, porque as paradas do agente já notificam pelos hooks e pelo 7501)
  (teste 24 de 2026-11-14). Kitty keyboard e OSC 9;4 só voltariam fingindo ser outro terminal:
  trocar o `TERM_PROGRAM` pede outra ADR, e a decisão é do dono.

## Detalhes da fase E1 (2026-11-15)
- **Uma conexão por painel**, presa a uma sessão: abrir (`open`) ou religar (`attach`); fechar a
  conexão é soltar a sessão, que segue rodando; `close` encerra (SIGHUP e, 200 ms depois, SIGKILL).
- **O master do PTY vai ao app** junto do `ready` (SCM_RIGHTS): o app escreve, redimensiona e lê o
  programa em primeiro plano direto nele, como hoje; o protocolo só leva a saída, o fim e a lista.
  O daemon confere com `getpeereid` que o outro lado é o mesmo usuário.
- **O socket leva a versão no nome** (`terminal-1.sock`), além do aperto de mão: um app atualizado
  com o mesmo protocolo religa às sessões do daemon velho; com outro, sobe o seu ao lado.
- **Os modos fora do buffer:** o daemon lê da saída inteira os modos DEC (`CSI ? n h/l`) e a pilha do
  teclado kitty, sem modelo; ao religar, manda depois do buffer só o que ele sozinho deixaria
  diferente.
- **Sem timer:** SIGCHLD acorda o laço por um pipe; parado, o daemon só espera o `poll`. Iniciado e
  ninguém conectou em 10 s, sai.

## Detalhes da fase E2 (2026-11-15)
- **"Mantido pelo launchd":** o app inicia o daemon com `posix_spawn` numa sessão própria (SETSID),
  sem nenhum descritor do app; quando o app sai, o daemon passa a ser filho do launchd. Sem
  LaunchAgent: um job do launchd com KeepAlive o reiniciaria depois de sair por não ter sessão, e o
  SMAppService mostraria o aviso de item em segundo plano. Enquanto o app roda, uma thread dele colhe
  o daemon quando ele sai (sem zumbi).
- **Sai depois de 3 s vazio**, não na hora: a checagem do socket pelo app e o "religar" recusado antes
  de abrir uma sessão nova são conexões que vêm e vão; saindo na hora, o daemon saía antes da sessão
  do app chegar (achado no teste com o app de release).
- **Reinício do Mac:** no SIGTERM o daemon grava a saída de cada sessão em
  `…/Cadex/scrollback/<nome>.raw` (0600) e sai; o app mostra o arquivo num shell novo e o apaga.
- **Só a janela principal mantém:** as janelas do ⌘N não salvam spaces, então ninguém religaria os
  terminais delas.

## Alternativas recusadas
- **O daemon guardar o modelo e mandar o estado da tela:** o daemon carregaria a libghostty e o
  modelo inteiro de cada painel; só volta à mesa se a recomendada falhar no `make perf` ou na
  fidelidade do scrollback.
- **Hook `http` em 127.0.0.1:** mais rápido (0,3 ms), mas a porta muda a cada abertura do app e
  fica presa no `--settings` de sessões que sobrevivem a ela; e TCP não diz o usuário do outro lado.
- **Um socket só para tudo:** o daemon do terminal fala só com o app, e misturar os dois
  protocolos daria a qualquer sessão com token uma porta para os PTYs.
- **Ficar no fim do log para o estado:** chega atrasado (lido numa parada) e não vale para sessões
  fora do Cadex nem para o texto da pergunta; o 7501 dá isso na hora.

## Consequências
- Specs: `docs/spec/terminal.md`, `docs/spec/tabs.md`, `docs/spec/spaces.md`, `docs/spec/agents.md`.
  Plano 19, fases B (app.sock, hooks, 7501) e E (daemon).
- O `make perf` ganha cenários com o daemon (10 terminais, com e sem janela) e com hooks a cada
  segundo; tudo desligado tem de dar os números de hoje, e o daemon sem sessão não aparece no `ps`.
- O protocolo do daemon é do Cadex e versionado; o 7501 e os hooks são do Claude Code e podem
  mudar: o que não ler é pulado.
