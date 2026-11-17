# app — entrada do app macOS

## O que eu quero
- Só o ponto de entrada: criar o NSApplication, as janelas e ligar as features.
- Várias janelas (⌘N, window.new): cada uma com workspace, projetos, explorer, busca, git e comandos
  próprios; só a principal (a que abriu com o app) salva os projetos (docs/spec/workspace.md).

## O que eu não quero
- Lógica de feature aqui. Cada coisa que a janela mostra vem de uma feature, pela porta de
  entrada dela (os tipos `public` do módulo).

## Como eu quero
- `PaletteWiring.swift`: a paleta nas cores do tema, os prefixos do ⌘K (`/` arquivos, `#` texto,
  `@` abas e projetos) e as aberturas (`openers`), primeiro no ⌘K; o "+" das abas mostra as que saem
  da aba (`newOpeners`) e o "+" do cabeçalho de cada painel as que abrem ao lado (`besideOpeners`),
  com maximizar e fechar (`paneMenu`).
  Comando novo que abre algo (terminal, arquivo, web, janela) entra nos `openers` daqui e nos de
  `../../windows/app/app_commands.zig`, e na lista "Abrir" de `../../../docs/spec/command-palette.md`.
- `ProjectsWiring.swift`: os projetos na janela (plano 27; abas de cada projeto ligadas à barra de status e ao
  preview, documentos reabertos, pasta do workspace devolvida); `tabs` da `WindowSession` é sempre a
  do projeto que aparece, então os comandos agem nela. Janela aberta pelo ⌘N tem projetos sem arquivo. project.new (`chooseProjectFolder`) pede a pasta, abre-a no workspace e mostra o projeto dela; aberto com uma pasta na linha de comando, os projetos voltam e a pasta vira o projeto dela (`startProjects`).
- `FolderFollow.swift`: o workspace segue o terminal com foco; a cada `cd` vai para a raiz do
  repositório git da pasta (ou a própria pasta), a menos que explorer.followTerminal desligue.
- Antes de montar qualquer tela, `main.swift` define Strings.language pelo general.language (ADR
  0015); "Reabrir agora" nas configurações e a atualização (`startUpdates`) saem como de costume e um
  shell abre o Cadex de novo (`openAgain`), levando as variáveis CADEX_ (uma instância de teste
  reabre em segundo plano, com o arquivo de projetos dela).
- `main.swift` (AppDelegate) guarda o que as janelas dividem: configurações, a janela de
  configurações, o keymap e o despachante de atalhos, que trocam para os comandos da janela com
  foco (`sessionBecameKey`). Abre a janela principal e as do ⌘N (`newWindow`, na pasta da janela de
  onde veio, deslocada um passo). Sair pergunta uma vez pelos programas e arquivos de todas as
  janelas.
- `WindowSession.swift`: uma janela. Cria o `WorkspaceFolder`, o explorer, a busca, o git e os projetos
  dela; como delegate da janela pergunta às abas antes de fechar (shouldCloseAll) e, fechada,
  encerra os shells dela (`closeAll`). `SessionCommands.swift` registra os comandos de cada feature
  no registro da janela (e window.new, view.toggle-sidebar e git.show da casca) e liga a barra de
  status ao terminal com foco. Pastas e arquivos da linha de comando ou soltos no ícone do Dock
  (`application(_:open:)`, o Dock só com o pacote .app do plano 7): pasta vira workspace, arquivo
  abre numa aba, endereço http(s) abre no preview. `FileOpener.swift` decide o que abre (mídia pelo
  tipo, o resto no editor; diffs do git num DiffDocument, o histórico num HistoryDocument que recebe
  as mudanças em .git, páginas web num PreviewDocument) e onde: ao lado do painel com foco ou em
  nova aba, por general.openFiles (opensBeside em `SettingsBridge.swift`), ou pela escolha do explorer; quem
  pede (o histórico abrindo um diff) fica no painel dele. `makeDocument(identity:)` refaz os
  documentos salvos nos projetos. O elemento escolhido num preview vai por `ElementPickDelivery.swift`:
  colado sem Enter no terminal do agente, que ganha o foco, ou copiado (⌥, preview.pickTarget em
  `SettingsBridge.swift`, ou nenhum agente). Passa as mudanças do disco aos documentos abertos e monta a aparência do editor (`EditorLooks`).
- A casca da janela: título transparente com barra de ferramentas compacta (ela posiciona os
  botões da janela); `TitleBarView.swift`, a barra de título da moldura nova (plano 26, fase A;
  `../../../docs/design/work-frame/screens.md`, TitleBar; components.titleBar): 44 pt, com os
  botões da janela descidos para o meio dela a cada mudança de tamanho e de foco (a barra compacta
  os centra em 38), a busca `TitleBarSearch.swift` ("Search ⌘K", abre a paleta), "projeto ›
  tarefa" (`location(of:)`: `<repo>.worktrees/<tarefa>` é o projeto e a tarefa), as abas e "+",
  e à direita o sino com o número (`setBell`, de `AgentsAttention.swift`) e o botão do painel da
  direita (inspector.toggle, aceso com ele aberto; `setInspectorOpen`); o café e a
  atualização foram para a barra de status (fase B, `StatusBarItems.swift`); o botão da barra
  lateral, o de space e o das configurações saíram (⌘B, ⇧⌘S e ⌘, no ⌘K, nos atalhos e no menu). Cada botão é
  um `TitleBarButton.swift` (components.titleIconButton: 30 pt, aceso quando o que abre está
  aberto, com o número do sino), todos por comando; nada de valor digitado
  (`../../../tools/check_design_literals.py`), `WorkspaceView.swift` (painéis arredondados de `PanelView.swift`,
  painel lateral recolhível, barra de status) e `TreeWiring.swift` (plano 27 fase B: a árvore da feature `sidebar`, colada à esquerda: o modelo
  juntado dos projetos, das worktrees de cada um, listadas fora da linha principal, do estado do
  agente de cada terminal e da conta do agente na pasta da tarefa; a escolha leva à aba, à tarefa ou
  ao projeto; sidebar.find; na fase B2, o +/− de cada tarefa pelo ReviewTally, a idade e a novidade
  de cada estado, o que espera e o menu da tarefa pelos comandos dela, `treeMenu`) e `CustomizeWiring.swift` (`openCustomize` abre a janela Customize única
  na aba pedida, com a da barra de status e a das contas desta janela, nas cores do tema como as
  configurações e não nas da janela, e a repinta quando o tema muda) e
  `StatusBarWiring.swift` (os itens Git branch e Terminals, e os lados salvos) e `StatusBarItems.swift`
  (plano 26, fase B: Project com o branch, Agents em duas contagens com o ponto de estado, Memory,
  o café e a atualização, que saíram da barra de título; `showPower`/`showUpdate` os atualizam). `AgentsLaunch.swift`:
  esconder contas guardando quem está logado (os ids do oauthAccount, nunca o login), a aba Accounts do Customize e o clique numa conta: o agente dela
  já rodando num terminal do Cadex vem para a frente (o usado por último, em qualquer janela); sem
  nenhum, abre no terminal com foco (no prompt) ou numa aba nova. `AgentsAccounts.swift`: as contas
  gerenciadas (plano 18, fase C): pedir o nome e abrir a aba com o claude da conta nova pelo kit,
  conta ativa no settings.json, sincronizar, compartilhar numa conta antiga mostrando antes o que
  muda, cópia própria, voltar a seguir e remover (só as do Cadex, para a lixeira). `AgentsHistory.swift`:
  a página History e o que cada ação faz (aba com o comando, área de transferência, Finder,
  workspace; a conta para continuar escolhida no ⌘K) e `continueInAgent` (o "Continue in…" do plano 22
  fase E: com memory.enabled, uma aba na pasta do projeto com o `cadex continue` da conta). `AgentsAttention.swift`: a atenção (plano 19,
  fase C): junta o que cada terminal de cada janela relatou (aviso TerminalView.agentDidChange), põe
  as permissões do socket no quadro, leva um cartão ao terminal dele, o número do sininho em cada
  janela e o do Dock, e a página do sininho. `WorktreesWiring.swift`: as tarefas (plano 19, fase D):
  New Task pede o nome, mostra o que pede um sim (a pasta, os hooks; recusar a pasta deixa
  escolher outra raiz, que vira worktrees.root), cria pelo núcleo e abre uma
  aba com os hooks e o agente (kit, conta do projeto ou a ativa); o aviso da confiança na primeira
  tarefa (a do repositório, aceita uma vez na aba da tarefa); abrir, remover sem perder trabalho, comentar, os hooks de preparo. O explorer é criado
  junto com os comandos, antes de as configurações montarem os atalhos.
  As cores vêm do tema; a cor da moldura vai na janela, não numa camada da view, porque uma
  camada pintada cobria os botões da janela.
- `InspectorWiring.swift` (plano 26, fase C): o painel da direita da feature `inspector`, colado à
  direita entre as barras: Changes (o painel do git), Files (a árvore do explorer), History (o
  histórico compacto, feito na primeira vez que a aba aparece) e Memory, cada aba com os botões de
  antes; a linha de contexto com a pasta, o branch (o clique troca) e a memória do projeto;
  inspector.toggle (⌥⌘I) e inspector.visible, inspector.tab e inspector.width (a borda) salvos; numa
  janela abaixo de 1000 pt, abrir o painel recolhe a barra lateral e fechá-lo a devolve
  (`WorkspaceView.swift`); git.show, explorer.focus,
  git.show-history e memory.show abrem a aba deles (WorkspaceView.showInspector).
- `AgentToolsWiring.swift` (plano 20, fase B): o pedido de comando do agente acha o terminal dele
  (pela sessão do kit, senão pelos pids acima do `cadex`), confere agentTools.enabled e a lista do
  agente e roda na janela daquele terminal, com a pasta e a conversa; abrir arquivo e diff (só dentro
  da tarefa), avisar (notificação e feed), preview.open com url=, a lista de sessões no ⌘K; o
  navegador do agente (fase C): o primeiro goto abre um preview ao lado do terminal dele, que fica
  sendo a aba daquele terminal (`AgentPreviewTabs`), e os pedidos respondem quando a página responde.
- `TypedClaudeWiring.swift` (plano 22, fase C): o kit do `claude` digitado numa aba zsh; só para
  quem tem o shell de um terminal do app acima (`shellPid` de todos os terminais, de todas as janelas
  e projetos), pelo SessionKit.typedLaunch. O `main.swift` põe as variáveis da integração do zsh no
  ambiente antes de abrir qualquer terminal (`exportTypedClaudeEnvironment`; numa instância de teste,
  também o CADEX_APP_SOCKET dela, para as abas não pedirem ao app do dono).
- `AgentsHibernate.swift` (plano 19, fase F): os hooks guardam no terminal o que traz o agente de
  volta; um relógio só, armado para o primeiro agente parado (agents.hibernateAfterMinutes, ninguém
  olhando), encerra com SIGTERM e marca a aba; o foco no terminal digita o `--resume` pelo kit; o fim
  de um agente que saiu sozinho mostra "Reiniciar"; agents.hibernate e agents.restart agem no
  terminal com foco. Só sessões abertas pelo Cadex (têm hooks).
- `ComputerUseWiring.swift` (plano 20, fase E): liga a feature computer-use às configurações
  (computerUse.enabled, allowedApps, blockedApps; o sim do dono é salvo), pergunta ao dono num alerta
  "o agente quer usar <app>", explica ao ligar e abre os Ajustes da Acessibilidade e da Gravação de
  Tela (computer-use.open-permissions); desligar para o que estiver agindo.
- `ReviewWiring.swift` (plano 21, fase B2): registra os comandos da revisão; git.review-open revisa
  o repositório da pasta do terminal com foco (senão a do workspace) contra onde a tarefa começou (o
  branch que o New Task guardou, pela worktrees); Tasks, o grupo da tarefa em Agents e o cabeçalho do
  Git rodam o mesmo; os botões da aba salvam git.reviewContextLines, git.reviewWrap e
  git.reviewShowWhitespace; mudança no disco dentro do repositório relê a aba.
- `ReviewCommentsWiring.swift` (plano 21, fase D): os comentários da feature review por worktree
  (ReviewCommentsHub, divididos pelas janelas) viram as anotações da aba de revisão, recolocados a
  cada leitura; o "+" e o c abrem o editor; o clique num comentário oferece editar e apagar (pelos
  ids); enviar cola, sem Enter, no agente da worktree que aceita colagem segura, senão copia com aviso;
  os dois casos vão para o histórico.
- `ReviewAuthorshipWiring.swift` (plano 21, fase E): com review.authorship o kit ganha o hook
  PostToolUse (`cadex hook PostToolUse`); cada edição vai ao rastreador da worktree do arquivo (achada
  fora da linha principal), as mudanças no disco e cada leitura da revisão comparam, e a aba ganha as
  marcas (review.toggle-authorship, review.export-authorship); remover a tarefa esquece a autoria.
- `MemoryWiring.swift` (plano 22, fase C): com memory.enabled o kit ganha a parte da feature memory
  (os hooks `cadex memory-hook` e a env do engine; com memory.shareAcrossAccounts desligada, a
  workspace por conta), aplicada pelo `SettingsBridge.swift`; e `startMemory`, ao abrir, aquece o
  engine uma vez por versão (`../features/memory/MemoryWarmUp.swift`); fase F: a tarefa que vira
  "review" (WorktreesController.onStatusChange) deixa o pedido de consolidação para as sessões cujo
  terminal está na pasta dela (`agentResume`), e memory.consolidate-now cola o pedido, sem Enter, no
  agente com foco; fase G: o agent.json do agente de memória a cada mudança das configurações
  (memory.backgroundAgent só vale com a memória ligada; as contas pelas de Agents) e
  memory.bootstrap (a estimativa num alerta antes, só roda no sim), memory.run-dream e
  memory.pause-agent, todos pelo `cadex memory-agent`. `MemoryPageWiring.swift` (fase H): a página
  Memory na barra lateral, com as contas e o "Open the Session" pelo índice do History (vigiado só com
  a página na tela); abrir uma página autoriza a pasta da wiki antes; o ⌘S (editor.save) num .md de
  uma wiki roda o `reindex` do projeto, e a edição vira commit.
- `MachinesWiring.swift` (plano 23, fase B): o grupo "Tailnet" da feature machines no cartão do ssh
  (`attachMachines`, chamado pelo `SSHWiring.swift`), lido só com o cartão aberto, e o
  machines.connect: aba nova com `ssh '<usuário>@<máquina>'`, o usuário pedido uma vez por máquina
  (o deste Mac sugerido; ⌥↩ pergunta de novo) e guardado em machines.users.
- `EnvironmentWiring.swift` (plano 23, fase E): New Task num repositório com receita sobe o ambiente
  (os hooks de preparo antes, numa aba) em vez de abrir o agente no Mac; numa tarefa remota, pelo
  contexto do Docker da máquina; a máquina da receita vem escolhida no "Run on"; os quatro comandos;
  hibernar um agente cuja pasta é de uma tarefa com ambiente o suspende, relançar e abrir a tarefa
  retomam; remover a tarefa pergunta se destrói o ambiente (marcado).
- `DockerWiring.swift` (plano 23, fase D): machines.docker-context digita `export
  DOCKER_CONTEXT='<máquina>'` (ou `unset`) no shell da aba com foco, ou numa aba nova se um programa
  roda nela (o terminal não tem ambiente por aba); o item Docker da barra de status mostra o da aba
  com foco; o shell de um contêiner numa aba e a porta no preview. `MachinesWiring.swift` também
  liga TerminalView.isOwnHost ao `isMachine` (a oferta do preview para `http://ubuntu-dev:3000`).
- `RunOnWiring.swift` (plano 23, fase C): o "Rodar em" no New Task (o nome e a máquina num alerta;
  as máquinas são os hosts do ~/.ssh/config e as da tailnet online), a pasta do repositório lá
  perguntada uma vez, clonar só com sim, a aba `ssh -t` com os hooks e o `claude`, abrir e remover a
  tarefa remota, a sessão remota em Agents abrindo o shell da tarefa; e `startRemoteAgents`: com uma
  página Agents na tela, o `claude agents --json` de cada máquina com tarefa, por ssh, a cada 30 s.
  agents.mute-machine (fase F) lista este Mac, os hosts e as máquinas e liga ou desliga cada uma em
  agents.mutedMachines. `MachinesWiring.swift` entrega a conexão aceita pelo listener da tailnet ao
  servidor do app.sock (`serveRemote`). Fase G: `startPreviewSharing` põe na barra de todo preview o
  botão de compartilhar, um menu com machines.share-port, machines.share-public (apagado sem a
  permissão do Funnel) e machines.stop-sharing (apagado sem nada compartilhado), cada um pelo id; `shareActions` dá a porta do preview com foco, confirma o
  Funnel e mostra o endereço com Copiar e Abrir.
- `RaceWiring.swift` (plano 24, fase C): registra os comandos da corrida; orchestration.toggle
  mostra antes o que muda ao ligar; orchestration.new-race abre o formulário (contas com a do
  projeto primeiro, as máquinas do "Rodar em"), confere antes de criar (RaceLaunch.check, a
  confiança pela conta de cada concorrente local), pede uma vez o que o New Task pediria (a pasta,
  hooks novos) e cria por concorrente a worktree pelo `plan`/`make` da worktrees e uma aba com os
  hooks e o `cadex claude --cadex-prompt-file` do kit; numa máquina remota, a worktree pelo
  `makeRemote` (a pasta do repositório lá já lembrada), o prompt pelo `uploadPrompt` e a aba `ssh
  -t`. `RaceBoardWiring.swift`: o quadro numa aba (`RaceWatch`: os quadros abertos, o diff de cada
  concorrente contado fora da linha principal pelo `ReviewTally`, um relógio de 15 s só com quadro
  aberto ou agente local de corrida trabalhando, e o aviso TerminalView.agentDidChange); o estado
  de cada concorrente pelo terminal achado pela sessão do kit (agentResume.kitSession), o custo
  pelo `SessionCost`, o remoto pelo `claude agents --json` da Agents; passou do teto da corrida
  (gasto ou minutos), SIGTERM como na hibernação; escolher o vencedor oferece descartar os outros;
  descartar para os agentes, apaga as pastas direto pela worktrees (sem Lixeira, o dono em
  2026-11-16) e deixa as branches; apagar as branches lista só as que restam, e a apagada não volta
  à lista.
- `RunWiring.swift` (plano 24, fase D1): registra os comandos da execução; New Run (nome e teto,
  no repositório da janela, o dono coordenando) abre a página; Add Task; as dependências mudadas
  (o ciclo recusado pelos títulos); tentar de novo passa pela folha do despacho; marcar concluída;
  parar (despacho, com confirmação; um que espera vaga só sai da fila) e a execução manda SIGTERM
  ao agente achado pela sessão do kit e passa as vagas à fila. `RunDispatchWiring.swift`: a folha
  do despacho (o prompt inteiro, a conta, o modelo, o modo de permissão, a branch de partida ou um
  terminal parado do repositório, o teto), as conferências (RunLaunch.check; sem confiança, "Open
  Claude to Trust" abre uma aba com o `claude` da conta no repositório), o que o New Task pediria,
  a fila quando os agentes vivos (corridas e execuções) chegam a orchestration.maxAgents, e o
  lançamento: o despacho gravado, a worktree pelo `plan`/`make` e a aba com o `cadex claude
  --cadex-prompt-file` e o CADEX_DISPATCH_ID na sessão, ou o comando no terminal reaproveitado.
  `RunPageWiring.swift`: a página numa aba (sem relógio próprio) e o `RunWatch` (um relógio de 15 s
  só com despacho vivo, esperando vaga ou terminado há menos de 2 min, e o aviso
  TerminalView.agentDidChange, que redesenha as páginas): grava o custo, sinal de vida pelo hook,
  falha o despacho cujo agente saiu ("exited without reporting", com 20 s de folga para o shell
  começar; o app reaberto faz o mesmo com os que ficaram), para a execução no teto e esvazia a fila.
  A corrida também conta os agentes das execuções no teto. `RunAgentWiring.swift` (fase D2): os
  comandos do agente pelo `cadex run` (o pedinte achado pela sessão do token, `RunAgentAPI`), a
  pergunta ao dono no feed de atenção e na notificação, as tarefas que começam sozinhas
  (`dispatchOnTheirOwn`, depois de cada mudança e a cada volta do relógio; a que não começa fica
  "falhou"), os portões e a resposta do dono, o "stalled?" avisado uma vez por despacho, o agente
  coordenador numa aba no repositório (`launchCoordinator`, o objetivo por arquivo) e, no
  AppDelegate, cada hook de uma sessão de despacho como sinal de vida (`noteRunHook`). Parar a
  execução, pelo dono ou pelo teto, encerra também o coordenador; o custo dele conta no teto. New
  Run e New Race partem do repositório principal (`mainRepository`) mesmo com o foco numa worktree
  de tarefa. O kit libera os comandos de reporte no Claude Code (`../app/SettingsBridge.swift`). `RunPerfHooks.swift`: CADEX_PERF_RUN
  (uma execução com tarefas que se despacham sozinhas, com `markDoneWhenFinished`,
  `markDoneWhenFailed` e `stopFirstAfter`, anotada em `out`), CADEX_PERF_RUN_FORM (preenche as
  folhas), CADEX_PERF_SHEETS (anota cada folha no log e a responde como o clique no primeiro botão;
  "Open Claude to Trust" só numa conta do Cadex) e CADEX_PERF_PRESS (aperta pelo título um botão da
  janela, por `performClick`; `page` traz a página da execução): a tela bloqueada não deixa a
  acessibilidade ver a janela (2026-11-16).
- `AutomationWiring.swift` (plano 24, fase E): os comandos das automações; ligar mostra antes a
  posição dos termos e o aviso do item em segundo plano; New Automation (nasce desligada, abre o
  histórico); ligar uma mostra o que roda, onde, em qual conta, como é pago e o teto; o LaunchAgent
  segue as ligadas (`syncAutomationAgent`: numa instância de teste, as pastas CADEX_ dela, o
  executável e o socket dela no plist). `AutomationRunWiring.swift`: a agenda conferida ao abrir,
  ao acordar o Mac (NSWorkspace.didWakeNotification) e no pedido do job (`onDue` do servidor); a
  execução (as recusas viram "failed" no histórico; a worktree nova pelo `plan`/`make` ou a pasta
  fixa; o prompt por arquivo; a aba na janela principal sem trazê-la para a frente; o computador
  acordado pela power, `hold(job:)`); o `AutomationWatch`, um relógio de 10 s só com execução
  rodando ou terminada há menos de 2 min (o custo final): concluída quando o agente para depois de
  trabalhar, falhou quando sai, no teto o agente é encerrado ("hit the cap", ou "stopped waiting"
  esperando permissão); o id do Claude e o caminho do transcript; o aviso no feed e na notificação.
- `ProgramNotifications.swift`: a notificação pedida por um programa num terminal (OSC 777, OSC 9)
  vira uma do macOS (terminal.programNotifications), uma por terminal, não enquanto você o olha; o
  clique vem pelo AgentNotifier.onOpenTerminal (o único delegate do centro) e leva ao terminal.
- `PerfHooks.swift`: só para o `make perf` (`../../../tools/perf/run.py`): cada variável CADEX_PERF_
  faz a instância de teste agir sozinha em horas marcadas (abrir a conversa de um subagente, abrir
  abas, abrir e rolar a revisão da pasta com CADEX_PERF_REVIEW, abrir duas vezes o grupo das máquinas da tailnet com CADEX_PERF_MACHINES); sem a variável, nada roda.
  `RacePerfHooks.swift` (plano 24): CADEX_PERF_RACE, um JSON com uma corrida que começa sozinha sem
  folha (e, com `pickAfter`, o #1 vence e os outros são descartados), anotada em `out`; CADEX_PERF_RACE_FORM
  preenche a folha "New Race" quando ela abre (a acessibilidade não alcança a folha); usado no
  teste da corrida no app e no `make perf` da fase F. Uma instância assim usa as pastas próprias
  CADEX_ORCHESTRATION_DIR, CADEX_PROMPTS_DIR, CADEX_KIT_DIR, CADEX_WORKTREES_FILE e CADEX_USAGE_DIR.
- Tela cheia: a barra de ferramentas (vazia, só dá a altura da barra de título) some ao entrar e
  volta ao sair, porque o macOS a punha numa faixa por cima da barra do app. Tamanho mínimo da
  janela 480×300.
- `WorkColors.swift` (plano 15, fase D): as cores de projeto e de aba pelo nome, desenhadas com o ANSI
  do tema; registra project.set-color (space.set-color, o id antigo, até o plano 28) e tab.set-color
  (lista no ⌘K) e põe a cor da aba ativa, ou a do projeto, no lugar do destaque da janela (workColor do WorkspaceView). O clique direito numa aba mostra
  `tabActions` (`PaletteWiring.swift`). `main.swift` chama
  UILooks.configure com o zoom, a densidade e a fonte da interface antes de qualquer tela.
- `MenuBarItem.swift`: o símbolo do Cadex na barra de menus do macOS (NSStatusItem), desenhado por
  `CadexMark.swift` com os caminhos do `docs/cadex-icon.svg`, branco com o manter acordado
  ligado, com a chama (fire-simple do Phosphor fill) saindo do braço de cima do >, e cinza desligado (o logo cheio nos dois); o clique roda power.toggle.
- `WindowBackdrop.swift`: imagem de fundo atrás da área do terminal (desfoque calculado uma vez) e,
  com vibrância, a moldura fosca; depois de ligar, os botões da janela voltam para cima da camada.
- Sem pacote .app (make run), `main.swift` põe o ícone de `docs/cadex-icon.png` no Dock; no .app ele
  vem do AppIcon.icns.
- Abrir para teste com CADEX_BACKGROUND=1: a janela aparece sem tomar o foco do teclado. Abas, projetos e a paleta
  entram aqui conforme as features existirem.
- Barra de título, botões dela, painel lateral e as abas dele medem por UILooks (`../shared/looks/CLAUDE.md`); a barra de título leva o zoom e não a densidade, porque o macOS põe os botões da janela.

## Como validar
- `make app` compila; `make run` abre a janela com um shell.
