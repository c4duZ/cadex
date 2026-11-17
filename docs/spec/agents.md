# agents

## Para que serve
Ver, sem sair do Cadex, os agentes de código que estão rodando (o que cada um faz, quem espera
resposta, os subagentes) e quanto do plano de cada conta já foi usado. O Cadex só observa: os
agentes continuam rodando em abas de terminal (`docs/adr/0019-agents-observe-only.md`). O Cadex
também cria contas, abre as sessões delas com o kit da sessão, guarda o histórico de todas e
continua uma conversa em outra conta, sem nunca tocar em token
(`docs/adr/0021-cadex-managed-accounts.md`).

## Comportamento
### Onde cada coisa fica (moldura nova, `../adr/0035-work-frame.md`)
As páginas Agents, Accounts, History e o sininho da barra lateral de ícones saem
(`../design/work-frame/inventory.md`); o que elas mostravam continua, nestes lugares:
- **As sessões:** as que rodam num terminal do Cadex aparecem na árvore (`sidebar.md`), no terminal e
  na tarefa delas, com o estado e os subagentes dobrados sob a linha; todas, inclusive as abertas
  fora do Cadex, aparecem na página do projeto (Recent conversations, plano 30) e no ⌘J. Até o plano
  30, as de fora do Cadex ficam no Arquivo e histórico (plano 27).
- **O uso das contas:** a etiqueta Agent usage da barra de status e o popover dela (`status-bar.md`),
  e "Accounts used here" na página do projeto.
- **O histórico das conversas:** "Archive & history" (⌘⇧H), no pé da árvore, abre no centro.
- **O sininho:** o sino da barra de título, com o número, abre um popover (seção Atenção).
Onde o texto abaixo diz "a lista de sessões", "o uso" ou "o histórico", vale o lugar novo; as regras
de leitura (só enquanto aparece) passam a valer para o lugar novo.

### Sessions
- A lista de sessões mostra as sessões vivas do Claude Code de todas as contas da máquina,
  agrupadas por projeto (a raiz do repositório git da pasta da sessão, ou a própria pasta). O grupo
  mostra o nome da pasta e quantas sessões tem; clicar no título recolhe ou abre o grupo.
- Cada sessão: um sinal de estado no meio da linha do nome, o nome, há quanto tempo está naquele
  estado, uma seta e, embaixo, o logo do provedor da conta, o branch e a conta ("main · Liderhub").
  - **Trabalhando**: o anel azul girando da peça de estado (components.stateGlyph).
  - **Esperando você**: o âmbar com halo da peça de estado; o sino conta.
  - Estado desconhecido: ponto cinza, com o nome do estado na dica.
- A lista acompanha na hora: sessão nova aparece, sessão encerrada some, estado muda, sem botão de
  atualizar.
- Clicar numa sessão (ou na seta) abre ou fecha os subagentes dela, desdobrando em 0,2 s (a seta
  gira junto): "4 subagents" e uma linha por subagente,
  com sinal (girando enquanto não terminou, pelo `finished` que o Claude Code grava ao fim; numa
  versão antiga sem esse campo, girando se escreveu nos últimos 30 s; senão ✓), a descrição e há
  quanto tempo. No máximo 10, os mais recentes primeiro. Funciona em pastas com espaço, "_",
  acento ou caminho longo (a pasta de conversas segue a regra do Claude Code; 2026-11-14).
- Duplo clique numa sessão que roda num terminal do Cadex foca esse terminal em qualquer janela,
  trazendo a janela para a frente e trocando de space e de aba se preciso; clique num subagente leva
  ao terminal da sessão dele (o terminal certo é o que tem o processo da sessão na frente). Sessão de fora do
  Cadex (outro terminal) mostra "outside Cadex" e o duplo clique mostra a pasta dela na árvore do
  explorer, quando ela está no workspace.
- Sessões em segundo plano (agent view, `claude --bg`) aparecem só enquanto rodam: o job tem um
  processo vivo entre os `workers` do daemon da conta. No grupo do projeto delas, com "in the
  background" na linha de baixo: trabalhando, ou esperando você quando o Claude Code diz "blocked"
  (a dica mostra o que espera, como "permission prompt"). Duplo clique abre uma aba na pasta dela
  com `claude attach <job>` (com a conta), onde a permissão ou a pergunta é respondida. As
  terminadas e as estacionadas (sem processo; o `claude agents --json` lista algumas "blocked" há
  meses, em pastas que nem existem mais, o dono em 2026-11-14) não aparecem. O mesmo job listado em
  várias contas aparece uma vez, na conta que tem a conversa dele. O `claude agents --json` só roda
  para a conta com algum job vivo, quando a pasta jobs/ muda, no máximo a cada 5 s; sem o `claude`
  instalado, não aparecem.
- As linhas acendem ao passar o ponteiro (0,12 s) e escurecem ao apertar: o clique responde antes
  de a ação acontecer. Antes o ponto ficava acima do nome e nada se mexia (o dono achou travado,
  2026-10-21); o clique indo ao terminal foi testado e desfeito no mesmo dia.
### Conversa do subagente
- Clicar num subagente (rodando ou já terminado) abre a conversa dele numa aba só de leitura, ao
  lado ou em aba nova como os arquivos (general.openFiles); de novo, vai à aba que já existe. Só
  abre por esse clique: não há comando nem atalho (o dono, 2026-10-21).
- O jeito é o do Claude Code no terminal, na fonte monoespaçada: a tarefa e as mensagens depois de
  "> " num fundo suave; as respostas com "●" e o Markdown delas (negrito, código, títulos, listas);
  cada ferramenta como "● Bash(make test)" e embaixo "⎿" com as três primeiras linhas do que voltou
  e "… +N lines" (em vermelho se falhou); um Edit mostra as linhas que saem em vermelho e as que
  entram em verde. O raciocínio e as marcas do Esc ficam de fora.
- Enquanto o subagente escreve, a aba acompanha: o sistema avisa que o arquivo cresceu e só o trecho
  novo é lido; se a vista estava no fim, ela desce junto.
- Peso: o log é lido em pedaços de 256 KB fora da linha principal; um resultado longo nunca é
  guardado (os primeiros 4 KB dão a prévia, as linhas são contadas enquanto os bytes passam). Uma
  vista de texto só, que desenha só o que aparece. Fechada a aba, nada fica: nenhuma leitura,
  nenhum arquivo vigiado. O `make perf` abre um log de 34 MB e confere aberto e fechado.
- Depois: a aba de terminal com um agente mostra o mesmo sinal de estado no título.

### Accounts
- O popover do uso (a etiqueta Agent usage da barra de status) mostra um bloco por conta: o nome (a organização da conta; renomeável), o
  plano, e duas barras: a sessão de 5 horas e a semana, com a porcentagem e quando reinicia.
- A barra fica na cor de alerta a partir de 70% e na de perigo a partir de 90%.
- Conta é cada pasta de configuração do Claude Code na pasta pessoal (`~/.claude` e as
  `~/.claude-*`) e cada uma do Codex (`~/.codex` e as `~/.codex-*` com login, pelo e-mail do
  login). Achar as contas não pede configuração. Cada cartão tem o logo do provedor
  (`docs/adr/0020-provider-logos.md`).
- O uso do Codex vem dos logs do próprio Codex (os limites que ele grava a cada uso), sem
  requisição nem token: é o número do último uso, com "em <hora>"; janela que já reiniciou desde
  então mostra 0%.
- O item Agent usage da barra de status mostra a conta do agente que roda no terminal com foco (o
  Claude Code pela sessão, o Codex pelo nome do programa); sem agente, a última mostrada. O ponteiro
  sobre ele abre um popover com todas as contas de todos os provedores, com plano, sessão e semana.
- O uso do Claude Code vem do `rate_limits` que o próprio Claude Code entrega à status line, nas
  sessões que o Cadex abre (o kit da sessão põe a status line do Cadex, que chama a do dono). Cada
  sessão grava o último valor da conta; o cartão mostra esse valor e, sem sessão aberta pelo Cadex
  agora, "em <hora>". Janela que já reiniciou desde então mostra 0%. Conta usada só fora do Cadex
  não tem número: o cartão diz "Open the agent from Cadex to see usage".
- O arquivo de uso é vigiado só enquanto alguém mostra o uso (o popover do uso ou o item da barra
  de status). "Refresh" no menu do cartão e no ⌘K ("Agents: Refresh Usage") relê o arquivo.
- O Cadex nunca lê, guarda, renova ou repassa login ou token, nem chama o serviço de uso. "Conta com
  login" é a que tem `oauthAccount` no `.claude.json` (lido, nunca escrito).

### Contas gerenciadas
- "Add Agent Account" (agents.add-account, no ⌘K) pede um nome, cria a pasta da conta em
  `~/Library/Application Support/Cadex/accounts/<nome>` (o nome em minúsculas, sem acento, com
  "-"), liga a configuração compartilhada e abre uma aba na pasta do workspace com `claude` naquela
  conta, pelo kit da sessão. O pedido do nome já diz para fazer o login ali com /login. O login é
  do próprio Claude Code; o Cadex não o vê. A conta aparece em Accounts quando o `.claude.json`
  dela ganha `oauthAccount`, com o nome dado (agents.accountNames).
- As contas que já existem (`~/.claude`, `~/.claude-*`) ficam onde estão: mover desloga.
- **Configuração compartilhada:** `~/.claude` é a conta padrão e a fonte. A conta gerenciada recebe
  link de tudo o que existe no topo da fonte, menos o estado da conta (`.claude.json`,
  `.credentials.json`, `projects/`, `sessions/`, `history.jsonl`, `jobs/`, `daemon/`, `state/`,
  `file-history/`, `paste-cache/`, `shell-snapshots/`, `cache/`, `backups/`, `downloads/`,
  `feedback/`, `session-env/`, `stats-cache.json`, `tasks/`, `todos/`, `telemetry/`, `statsig/`,
  `ide/`, `debug/`, `chrome/`, `daemon-*`, `.last-*`, os `policy-limits*` e `remote-settings*` da
  organização e os `*-cache.json`; os nomes vistos nas pastas do dono em 2026-11-14). Pasta
  desconhecida (como a de uma ferramenta instalada ali) também vira link.
  - Instalar uma skill, um plugin ou mudar o `settings.json` da fonte vale em todas na hora. O que o
    Claude grava num arquivo lincado, de qualquer conta, vale para todas.
  - Item novo no topo da fonte entra no próximo "Sync Agent Accounts' Config"
    (agents.sync-account-config), em todas as contas que seguem a fonte; ele diz o que ligou. Link
    para item que saiu da fonte é tirado.
  - "Use an Account's Own Copy…" (agents.use-own-copy, lista "conta › item") troca o link por uma
    cópia que deixa de seguir a fonte; "Follow the Default Account Again…"
    (agents.follow-default-config) desfaz, com a cópia indo para a lixeira.
  - Numa conta que já existia, "Share the Default Account's Config…" (agents.share-account-config) é
    opcional e mostra antes o que vira link e o que já existe ali; o que existe vai para a lixeira,
    nunca é apagado.
  - Uma conta segue a fonte quando foi criada pelo Cadex ou tem algum link para ela.
- **Conta ativa:** a das sessões novas abertas pelo Cadex (agents.activeAccount; vazia é a conta
  padrão). Escolhida no item Agent usage (clique direito: "New Sessions Use", com a marca na ativa),
  no ⌘K ("Set Active Agent Account", agents.set-active-account) e no clique direito do cartão em
  Accounts ("Use for New Sessions"). O cartão dela diz "· active".
- **Conta do projeto:** "Set This Project's Agent Account" (agents.set-project-account) dá ao
  projeto da janela (a raiz git do workspace) uma conta própria, que vence a ativa naquele projeto;
  "Use the Active Account" na mesma lista desfaz. Guardada em agents.projectAccounts; conta que não
  existe mais cai na padrão. Quem usa essas duas escolhas são as sessões novas sem conta escolhida
  (Nova tarefa, plano 19); clicar numa conta continua abrindo aquela conta.
- **Kit da sessão:** toda sessão que o Cadex abre (abrir o agente de uma conta, Retomar, Continuar em
  outra conta, e depois Nova tarefa) recebe a status line do Cadex, os hooks, skills e MCPs que as
  features acrescentam, os MCPs da conta padrão, `CLAUDE_CONFIG_DIR` da conta e o ambiente limpo
  (sem `CLAUDECODE` nem `CLAUDE_CODE_*` herdados). Os hooks do dono continuam rodando junto; a status
  line dele continua aparecendo, chamada pela do Cadex. Nada é escrito na configuração da conta.
- "Remove Agent Account…" (agents.remove-account) lista só as contas criadas pelo Cadex; depois de
  confirmar, a pasta vai para a lixeira e o Cadex esquece o nome, o esconder e a conta ativa ou de
  projeto que apontavam para ela. As contas de antes não são removidas: elas se escondem.

### Histórico
- Archive & history (agents.show-history, ⌘⇧H), no centro, lista todas as conversas de todas as
  contas: título (o que você deu com /rename, senão o que o Claude deu, senão o primeiro pedido),
  e embaixo pasta · branch · conta · há quanto tempo. A pasta é a de onde a conversa rodou (uma
  conversa do repositório retomada numa worktree aparece na worktree). Conversa sem mensagem
  nenhuma (aberta e fechada) não aparece. O primeiro pedido nunca é o resumo de uma compactação nem
  a marca do Esc.
- Busca por título, pasta, branch e trecho do que foi dito (as palavras como começo de palavra, sem
  acento nem caixa); agrupa por projeto (raiz git), pasta ou conta; escopo "This Project" (o projeto
  da janela) ou "All Projects".
- Duplo clique ou "Resume" (agents.resume-session) abre uma aba na pasta original (ou na pessoal, se
  ela sumiu) e digita `claude --resume <id>` na conta dona, com o kit da sessão. Sem prompt: o Cadex
  só digita o comando.
- "Continue in Another Account…" (agents.continue-in-account) escolhe a conta no ⌘K e digita
  `claude --resume <caminho da conversa> --fork-session` nela: a outra conta recebe a conversa e
  grava a cópia na pasta dela; o original fica intacto. Numa pasta que a outra conta ainda não
  confia, o próprio Claude Code pergunta antes. A cópia mostra a mesma conversa e o índice guarda de
  onde ela veio: as linhas copiadas levam o id da origem (em `sessionId` nas versões antigas, em
  `session_id` na primeira mensagem no 2.1.325); a conversa de um subagente dela é procurada também
  na conta de origem, onde ficou: a lista de subagentes de uma sessão continuada (na árvore)
  mostra os dela e os da origem, e a conversa de cada um abre do arquivo dele.
- Também no clique direito e no ⌘K: "Copy Resume Command" (agents.copy-resume-command, com o `cd`
  para a pasta), "Reveal Session Log" (agents.reveal-session-log, no Finder) e abrir a pasta da
  conversa no workspace. Pelo ⌘K, cada um abre a lista de conversas, buscada como a página.
- Peso: o índice (SQLite do sistema com FTS5, `~/Library/Application Support/Cadex/history.sqlite`)
  lê só o que foi acrescentado a cada arquivo, em pedaços fora da linha principal, nunca monta o JSON
  de linha que não interessa e nunca guarda resultado de ferramenta. A primeira leitura das contas do
  dono (236 conversas, 2,5 GB) levou 13 s com 97 MB de pico; depois, 0,01 s por passada (2026-11-14).
  Enquanto a primeira roda, a página diz "Indexing 120 of 236". Vigia as pastas de conversas só com
  a página (ou a lista do ⌘K) aberta; fechada, o índice fica em disco e nada roda. agents.history
  (ligada) desliga tudo: nada indexado nem vigiado. Linha que não lê (versão nova do Claude Code) é
  pulada e contada: "Some lines could not be read (N)" embaixo da busca.

### Estado exato (plano 19)
- Numa aba do Cadex, o estado de uma sessão vem do próprio Claude Code pelo OSC 7501 (`docs/adr/0022-terminal-daemon.md`):
  trabalhando (com a frase do que faz, "Creating empty file…"), esperando permissão (com o pedido,
  "approve Bash: touch x"), pergunta (com o texto e as opções), terminou, parado. Vale para um
  `claude` digitado à mão. Chave ou estado desconhecido é ignorado; frase ausente não quebra.
- Nas sessões que o Cadex abre, os hooks do kit (SessionStart, Stop, Notification,
  PermissionRequest, SessionEnd, CwdChanged) dão o que o 7501 não traz: o id da sessão depois de
  `/clear` e `--resume`, o arquivo da conversa e a pasta. Vão pelo `cadex hook` ao socket do app,
  com o token da sessão; o hook nunca espera o app (200 ms), salvo a permissão (ADR 0023).
- Sessão em outro terminal continua pelo registro dela e pelo fim do log numa parada.
- agents.stateHooks (ligada) desliga os hooks do kit; o 7501 continua.

### Atenção (plano 19)
- O sino (na barra de título, sempre à vista) conta os pedidos abertos de todas as
  sessões (permissão, pergunta) e os agentes que terminaram sem você ver; o mesmo número no ícone do
  Dock (agents.dockBadge). Ir ao terminal do agente marca como visto; "Mark as Unread"
  (agents.mark-unread, ou o clique direito numa linha do feed) volta.
- O popover do sino (400 pt; `../design/work-frame/screens.md`, seção Bell) tem duas vistas, "Needs
  you" (os cartões) e "Activity" (agents.show-feed): a linha
  do tempo de terminou, pediu permissão, perguntou, falhou e tarefa criada, de todas as sessões, a
  mais nova em cima, até 200, com filtro por tipo e por projeto; clicar leva ao terminal.
- O popover só acompanha as mudanças enquanto aparece; o número do sino é o mesmo do Dock e não lê
  nada a mais.
- Silenciar as notificações de uma máquina (agents.mutedMachines): este Mac, cada host do
  `~/.ssh/config` e cada máquina da tailnet (plano 23).
- Sessões remotas (plano 23, `docs/adr/0031-run-on-remote.md`): com uma tarefa remota à vista na
  árvore ou a página do projeto dela aberta, o Cadex
  roda `claude agents --json` por ssh (sem perguntar nada: uma máquina que pede senha fica de fora) em cada máquina onde uma tarefa do "Run on" está, ao abrir e a cada 30 s, e lista as
  sessões de lá no projeto, com "em <máquina>". Sem kit nem hooks lá, o estado é o que esse comando
  diz, e a notificação de "terminou" ou "esperando você" de uma sessão remota só vem enquanto a página
  está à vista (nada de cartão "Precisa de você" para elas); um duplo clique leva à aba ssh da tarefa.
  Nada à vista, nenhum ssh roda. agents.attention desliga o sininho, o feed e o número.

### Quadro "Precisa de você" (plano 19)
- agents.show-attention mostra um cartão por pedido aberto. Permissão: a ferramenta e o comando ou o
  arquivo, com Permitir e Negar (agents.approve, agents.deny), só por clique, com o diálogo da TUI
  aberto: quem responder primeiro vence (`docs/adr/0023-answer-agent-permissions.md`). Pergunta e
  plano: o texto e, numa sessão aberta pelo Cadex, a resposta ali mesmo
  (`../adr/0036-owner-words-reach-the-agent.md`): um campo "Answer…" para texto livre, ou um botão
  por opção quando a pergunta tem opções; o Cadex digita a resposta no terminal do agente só se ele
  ainda está naquela pergunta, e senão o cartão diz "The agent moved on". Todo cartão tem "Go to
  tab"; sessão aberta fora do Cadex tem só ele. O mesmo pedido de permissão aparece como cartão no pé do painel do agente
  (`tabs.md`, plano 28): responder num fecha o outro.
- O cartão some quando o pedido se resolve: pelo clique aqui, ou quando o agente deixa de estar
  "blocked" no OSC 7501 (respondido na TUI). O Claude Code não fecha o hook quando a TUI responde
  (teste de 2026-11-15), então é a saída do "blocked" que tira o cartão e fecha o hook que esperava.
- Sessão aberta fora do Cadex mostra o cartão sem Permitir e Negar (não tem o hook do kit).

### Hibernação (plano 19)
- Sessão que terminou, sem foco e parada há agents.hibernateAfterMinutes (padrão 30; 0 desliga) é
  encerrada; o Cadex guarda o id, a pasta, a conta, o comando e o token. A aba fica com ☾ e
  "Hibernando" na dica.
- Abrir a aba ou a worktree relança na mesma pasta e conta `claude --resume <id>`, pelo kit e com o
  mesmo token, sem prompt. agents.hibernate hiberna na hora.
- Agente que saiu mostra "Restart" (agents.restart), que relança igual.
- Como (2026-11-15): só sessões abertas pelo Cadex, que têm os hooks; "terminou" é o OSC 7501 em
  done ou idle, e o tempo conta desde então (trabalhar zera). Encerrar é SIGTERM no `claude`: ele sai
  em menos de 1 s, grava a conversa, e `--resume` a retoma (testado com a palavra-código). O comando
  volta como foi aberto: o kit guarda os argumentos de cada sessão junto do token (`--model`, o modo
  de permissões), sem o `--resume`/`--continue` de então. Não hiberna
  quem trabalha ou espera você (agents.hibernate recusa com um bip). "Restart" é um botão no canto do
  terminal quando o agente sai sozinho (fim da sessão sem processo depois); digitar o tira. Um texto
  digitado e não enviado no prompt do agente se perde ao hibernar.

### Notificações
- Quando uma sessão que trabalhava passa a esperar você, o Cadex manda uma notificação do sistema,
  escrita como as dos terminais e ferramentas de agente: o tipo no título, com o nome do agente
  (Claude ou Codex, pela conta): "Claude Wants to Run a Command" (Bash), "… to Edit a File"
  (Edit, Write), "… to Use <ferramenta>", "Claude Has a Question", "Claude Finished". O subtítulo é
  projeto · sessão · conta; o texto, o detalhe: o comando ou o arquivo, a pergunta (ou "A plan is
  ready for your review"), a primeira linha da última resposta.
- O motivo vem do fim do log da conversa (os últimos 64 KB), lido uma vez por parada: a última
  ferramenta pedida sem resposta é uma permissão, a de pergunta é uma pergunta, o fim de turno é
  "terminou". Sem dizer, "Stopped and waits for you", contado como pergunta.
- Sem imagem: à esquerda fica o ícone do Cadex, que o macOS não deixa trocar por notificação (só
  as de comunicação, com permissão paga da Apple, mostram a foto de quem mandou; a API privada do
  terminal-notifier saiu dele), e a imagem à direita, com o símbolo do tipo, destoava (o dono,
  2026-10-22, depois de pesquisa).
- Cada tipo toca o seu som, escolhido em Configurações › General ao lado da chave dele: um som do
  macOS (padrão: Funk, Ping e Glass), o alerta padrão, nenhum, ou um arquivo seu (.aiff, .wav,
  .caf); escolher toca o som. O macOS toca o som com a notificação (o Foco e a chave de som do
  Cadex nos Ajustes valem): o Cadex copia o escolhido para `~/Library/Sounds` como "Cadex
  Permission" (Question, Finished), onde o sistema procura os sons de um app fora de sandbox.
- Ao ir ao terminal de um agente, a notificação dele sai da Central de Notificações.
- Clicar leva ao terminal do agente, trazendo a janela, o space e a aba. Não avisa enquanto você
  olha aquele terminal na janela da frente. Uma notificação por sessão: a nova troca a anterior.
- Três chaves, cada tipo desligável sozinho: agents.notifyPermission, agents.notifyQuestion e
  agents.notifyFinished, ligadas por padrão; com agents.sessions desligado, nenhuma. Os sons em
  agents.soundPermission, agents.soundQuestion e agents.soundFinished ("none", "default", o nome de
  um som do macOS ou o caminho de um arquivo).
- "Send Test Notifications" (agents.test-notifications, no ⌘K) manda as três de exemplo; com as
  notificações do Cadex desligadas no macOS, abre a página dele nos Ajustes do Sistema.
- Qualquer estado depois de trabalhando conta como parada (idle, waiting e shell, este o de um
  turno que acabou de terminar, visto ao vivo em 2026-10-21); o fim do log diz o motivo, lido 1 s
  depois da parada (o estado muda antes de o log receber a marca do Esc) e nada se voltou a trabalhar.
- Parada por você (Esc; o log termina com "[Request interrupted by user…]") não avisa: você sabe
  que parou (o dono, 2026-10-21).
- Só no Mac por enquanto; no Windows chega com o port (lá dá para trocar o ícone da notificação).

### Agentes abertos com prompt (plano 24)
- Com a feature `orchestration` ligada, o Cadex abre agentes com prompt numa corrida, num despacho
  ou numa automação (`docs/adr/0033-cadex-launches-agents.md`, `docs/spec/orchestration.md`). São
  sessões do Cadex como as outras (kit, hooks, notificações, hibernação), e a linha delas em
  Sessions diz de onde vieram: "race · <nome> 2/3", "run · <execução> · <tarefa>" ou
  "automation · <nome>".
- O quadro "Precisa de você" recebe também as perguntas que um agente supervisionado faz pelo
  `cadex` (orchestration.ask), com "Open Run" em vez de Permitir e Negar.
- Relançar depois de hibernar é `--resume`, como sempre: o prompt inicial não é mandado de novo.

### Configurações
- Quatro chaves, cada uma desliga uma leitura por inteiro (nada vigiado nem lido):
  agents.sessions, agents.accounts, agents.history e, em ssh, ssh.ping. Ligadas por padrão, cada uma
  com a sua linha em Configurações › General ("Index conversation history" é a do histórico).
- O popover do uso: um bloco por conta (logo, nome, "· plano", quando zera, a barra e "84% of the
  5-hour window · 61% of the week"), e no pé "Open an agent on… · Add account · Accounts settings";
  a pasta fica na dica (`../design/work-frame/screens.md`, seção Anatomy).
- Conta sem `oauthAccount` não aparece em Accounts, no item de uso nem no cartão. "Login vencido"
  aparece quando uma sessão daquela conta falha com erro de autenticação ("Failed to
  authenticate…"), ou pelo `credential_expires_at` de um `claude -p` que o Cadex já rode por outro
  motivo; o Cadex não roda nada só para saber.
- Clicar numa conta com o agente dela já rodando num terminal do Cadex vai a esse terminal (o usado
  por último, se há vários; em qualquer janela), sem abrir outro.
- Sem nenhum, clicar abre o agente dela (ADR 0019): no terminal com foco, se ele está no prompt, ou
  numa aba nova na pasta dele, digita `claude` com `CLAUDE_CONFIG_DIR` da conta (ou `codex` com
  `CODEX_HOME`) e Enter; com agents.launchSkipPermissions, sem pedir permissões. Também no ⌘K ("Open
  an Account's Agent") e no clique direito.
- Esconder uma conta (clique direito, ou a chave em Customize › Accounts; agents.hiddenAccounts) a
  tira de Accounts, do item e do cartão (as sessões dela continuam em Sessions) e ela não é lida.
  Ela volta sozinha quando o `oauthAccount` dela muda (outra conta ou organização; guardado em
  agents.hiddenLogins na hora de esconder), nunca por um reinício de janela. Customize › Accounts lista todas, com o estado de cada uma, e a opção "Without
  permission prompts".
- Renomear (agents.accountNames, pelo botão direito no cartão): o nome novo vale em Sessions, nas
  notificações e na barra de status; vazio volta ao da organização.
- agents.accounts desliga a leitura do uso: nenhum arquivo de uso lido nem vigiado.

## Estados
- **Nenhum agente rodando**: "No agents running. Start one in a terminal: claude".
- **Claude Code não instalado ou nenhuma conta**: a página diz isso e Accounts fica vazia, sem erro.
- **Login vencido**: o cartão diz "Login expired. Run claude with this account to renew it." e a
  barra de status esconde a conta.
- **Uso antigo**: sem sessão do Cadex na conta, o cartão mostra o último valor, apagado, com
  "updated 3 h ago".
- **Sem uso nenhum**: conta que nunca teve sessão aberta pelo Cadex mostra "Open the agent from
  Cadex to see usage", sem barras.
- **Histórico indexando**: Archive & history mostra o que já leu e uma linha "Indexing 120 of 800";
  a lista cresce sem pular.
- **Leitura desligada**: a página explica qual chave está desligada, com o botão para ligar.

## Casos de borda
- O formato dos arquivos do Claude Code mudou (versão nova): o que não der para ler é pulado, a
  página mostra o que conseguiu e nada trava. Um aviso discreto: "Some sessions could not be read".
- Processo morto deixou o registro da sessão para trás: a sessão não aparece (conferido a cada 10 s
  enquanto alguém olha).
- Conta nova, sem nenhuma sessão ainda: a pasta sessions dela entra na conferência de 10 s.
- Duas contas da mesma organização: o nome ganha a pasta ("BKDG · bkdg").
- Duas sessões na mesma pasta: as duas aparecem no mesmo grupo, cada uma com o próprio estado.
- Muitas sessões (mais de 50): a lista rola e só as linhas na tela são desenhadas.
- Status line do dono quebrada ou lenta: a do Cadex grava o uso primeiro e mostra a saída da do
  dono como vier (vazia se ela falhar); a sessão não sente.
- Arquivo de uso quebrado ou com campo faltando: o cartão fica com o último valor bom.

## Critérios de aceite
- [ ] Rodar `claude` numa aba faz a sessão aparecer em até 1 s, no projeto certo, com a conta certa.
- [ ] Mandar uma mensagem troca o sinal para "trabalhando"; quando o agente termina, "esperando você".
- [ ] Fechar a aba do agente tira a sessão da lista.
- [ ] Os subagentes de uma sessão aparecem ao clicar, com descrição e tempo.
- [x] Com uma sessão aberta pelo Cadex em cada uma de duas contas, Accounts mostra as duas com os
      mesmos números do `/usage` de cada uma (bhband 4% e 56%, bkdg 60% e 36%, sessões ao mesmo
      tempo, 2026-11-14).
- [x] O Cadex nunca roda `/usr/bin/security` nem sai para a rede para ler uso: 6,5 min com o uso na
      tela, sem processo filho além do shell e sem socket de rede (`ps` e `lsof` no processo, a cada
      0,5 s), e nenhuma das strings do caminho antigo nos binários (2026-11-14). Falta a mesma
      conferência com `fs_usage`, que pede root.
- [ ] Com agents.sessions, agents.accounts e agents.history desligados, o Cadex não abre nenhum
      arquivo do Claude Code (conferido com `fs_usage`).
- [x] Sessão aberta pelo Cadex: a status line do dono aparece igual, os hooks dele rodam, o ambiente
      não tem CLAUDECODE nem CLAUDE_CODE_* herdados e o transcript é gravado (bhband, 2026-11-14).
- [ ] "Add Agent Account" cria a pasta e os links certos (nenhum item do estado da conta; uma pasta
      desconhecida da fonte também vira link) e abre a aba com o `/login`; depois do login, a conta
      aparece em Accounts. Conferido em 2026-11-14 até o login: conta real criada pelo código do
      app com 15 links (gsd-core incluído) e nenhum item de estado; o `claude` nela, pelo kit,
      chegou a "Select login method"; o estado novo nasceu na pasta dela e o ~/.claude não mudou.
      Falta o login, que é do dono.
- [x] Um MCP da conta padrão aparece na sessão de outra conta sem nenhum .claude.json mudar (servidor
      de teste passado pelo kit apareceu no `/mcp` de uma sessão da bhband, 2026-11-14).
- [x] A conta ativa se escolhe no clique direito do item Agent usage, no ⌘K e no cartão, e o cartão
      dela diz "active" (testes e PNG com as contas reais, 2026-11-14).
- [x] Uma skill nova em `~/.claude/skills` aparece na conta gerenciada sem nada a fazer (teste com
      pasta pessoal falsa; o link de pasta inteira já carregava skills no teste de 2026-11-14).
- [ ] Nenhuma conta que já existia muda de lugar nem perde o login; nenhum `.claude.json` muda.
- [x] History mostra as sessões de duas contas nos projetos certos; "Resume" abre na conta dona
      (as 236 conversas das quatro contas do dono; a conversa da bhband reaberta nela, 2026-11-14).
- [x] "Continue in Another Account" continua a conversa (a outra conta lembra o que foi dito), o
      arquivo original fica com o mesmo hash e a cópia vai para a pasta da outra conta (GIRASSOL-47
      lembrado na bkdg; e uma conversa longa, 198 pedidos e três compactações: a cópia levou tudo o
      que a conta original carregaria, 2026-11-14).
- [x] Um transcript crescendo só tem o trecho novo lido; formato desconhecido é pulado sem travar
      (testes; nas contas do dono, nenhuma linha ilegível).
- [x] Numa aba aberta pelo Cadex, pedir um `rm` mostra "esperando permissão" em até 1 s e o título
      da aba muda; um `claude` digitado à mão mostra trabalhando, permissão e pergunta (com o texto)
      só pelo OSC 7501. Conferido em 2026-11-15: pelo terminal do núcleo com o `claude` real
      (trabalhando com a frase, permissão "approve Bash: …", pergunta "answer: Você prefere azul ou
      verde? (Azul · Verde)") e pelas abas de verdade com um terminal real (o título vira "● <nome>"
      e a dica diz o pedido). A janela do app em si não foi fotografada (sem permissão de tela).
- [x] `/clear` e `--resume` mantêm o id certo; com o app fechado no meio, o próximo hook acha o app
      reaberto e o token ainda vale; com o app fechado, o Claude não espera o hook (o `claude` real,
      2026-11-15: SessionStart, /clear com o id novo, o socket fora e de volta, /exit).
- [x] Um processo sem token, ou de outro usuário, é recusado no socket do app (teste com socket de
      verdade; outro usuário pelo `getpeereid`, que o teste não tem como simular).
- [x] Permitir no quadro faz o comando rodar e fecha o diálogo da TUI; responder na TUI tira o
      cartão; nada é mandado ao agente sem clique. Conferido em 2026-11-15 com o `claude` real e o
      socket de verdade: a resposta do app liberou o `touch`; respondendo na TUI primeiro, o comando
      rodou e o hook ficou esperando (o cartão sai pela saída do "blocked", coberta por teste com o
      terminal real avisando o app). Negar: o agente recebeu "denied" com a mensagem.
- [ ] O número do Dock some ao visitar o terminal; "Mark as Unread" o traz de volta. A contagem e o
      "visto" têm teste; o ícone do Dock em si não foi fotografado.
- [ ] Depois do tempo, a sessão hibernada some do `ps`; abrir a aba retoma a conversa (a
      palavra-código lembrada). (2026-11-15, app de release, agents.hibernateAfterMinutes = 1: o
      `claude` saiu sozinho um minuto depois de responder, o shell e o app ficaram, e
      `claude --resume <id>` da conversa respondeu a palavra-código; o foco na aba digitando o
      `--resume` falta ver, sem permissão de clicar.)
