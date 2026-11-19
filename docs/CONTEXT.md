# Vocabulário do Cadex

Os termos que aparecem em conversa, spec e código, e o que significam aqui. Termo novo que surgir
numa conversa entra nesta lista. Entre parênteses, o nome usado no código.

## Estrutura do app
- **Núcleo** (`core`): biblioteca em Zig com a lógica que não depende de plataforma, exposta por uma
  API C.
- **App** (`apps/macos`, `apps/windows`): a interface nativa de cada sistema. Desenha, recebe
  entrada e chama o núcleo.
- **Feature**: um assunto do produto (terminal, explorer, source-control...). Tem pasta própria no
  núcleo e/ou no app, com o mesmo nome.
- **Porta de entrada**: a parte pública de uma feature. As outras features só usam isso.
- **Spec**: a descrição do comportamento de uma feature em `docs/spec/`. É a referência da reescrita.

## Janela e layout
- **Janela** (`window`): uma janela do app, com workspace, projetos, explorer, busca e git próprios.
  ⇧⌘N abre outra (o ⌘N é Nova tarefa). A **janela principal** é a que abriu com o app: só ela é
  salva e restaurada.
- **Moldura** (`work frame`): as quatro regiões iguais em toda tela, barra de título, árvore do
  trabalho, centro e painel da seleção, mais a barra de status (`docs/adr/0035-work-frame.md`).
- **Projeto** (`project`): uma pasta de código com os terminais, documentos e tarefas abertos nela,
  restaurado entre sessões. É o que antes se chamava **space** (`space`), agora sempre com pasta.
- **Tela de início** (`home`): o centro quando nenhum projeto está aberto: a caixa do pedido, os
  cartões Terminal, Agent, Task e Race e os projetos recentes.
- **Gaveta de terminais** (`terminal drawer`): os terminais rápidos fora de qualquer projeto, que
  sobem de baixo por cima do centro (⌃`).
- **Peça de estado** (`state glyph`): o sinal único de estado do app (trabalhando, precisa de você,
  pronto, falhou, parado, em revisão), igual na árvore, nas abas, no sino, no ⌘J, no quadro e no Dock.
- **Token de design** (`design token`): um valor nomeado dos mockups da moldura (cor, fonte, raio,
  espaço, medida de peça), em `docs/design/work-frame/tokens.json`, de onde o app gera os dele.
- **Aba** (`tab`): um item da barra de abas. Pode ser terminal, editor, preview, markdown, mídia,
  diff ou histórico do git.
- **Painel** (`pane`): uma divisão dentro de uma aba de terminal. Uma aba pode ter vários painéis.
- **Folha** (`leaf`): um painel final da árvore de divisões, que contém uma sessão de terminal.
- **Trilho** (`rail`, a feature `sidebar`): a faixa estreita na borda esquerda com os projetos
  (imagem, nome dado pelo dono, peça de estado), o "+", os ícones das páginas da coluna e, no pé,
  Projects, Automations e Remote (este só com algum host). Substituiu a árvore do trabalho (ADR 0038).
- **Coluna lateral** (`side column`, a feature `inspector`; nos textos, nunca "painel da direita"):
  ao lado do trilho, as páginas do projeto escolhido, uma por vez: Files, Changes, Sessions, Memory
  e Git graph, abertas pelos ícones delas no trilho (ADR 0038).
- **Sessão** (`session`): uma conversa de um agente numa conta. Nos textos, "sessão" (não
  "conversa" nem "arquivo"); a lista de todas é "All sessions".
- **Projeto fixado** (`pinned project`): fica no trilho mesmo sem terminal aberto; o clique abre um
  terminal na pasta dele.
- **Barra de status** (`status-bar`): a faixa inferior, montada com itens que quem usa escolhe e
  arrasta. **Item da barra de status** (`status item`): uma peça dela (pasta, ambiente, RAM, CPU, SSH...).
- **Conta** (`agent account`): uma pasta de configuração do Claude Code (`~/.claude`, `~/.claude-*`), com
  login e uso próprios. **Uso** (`usage`): quanto da sessão de 5 h e da semana a conta já gastou.
- **Conta gerenciada** (`managed account`): conta que o Cadex criou, na pasta dele
  (`~/Library/Application Support/Cadex/accounts/<nome>`), com o login feito pelo `claude` numa aba.
  As contas de antes ficam onde estão. **Conta padrão** (`default account`): `~/.claude`, a fonte da
  configuração compartilhada. **Conta ativa** (`active account`): a das sessões novas que o Cadex
  abre; a conta padrão de um projeto (`project account`) vence a ativa nele.
- **Configuração compartilhada** (`shared config`): os links que a conta gerenciada recebe para tudo
  do topo da conta padrão, menos o estado da conta (conversas, sessões, `.claude.json`, caches).
  **Cópia própria** (`own copy`): um item que deixou de ser link e não segue mais a fonte.
- **Kit da sessão** (`session kit`): o que o Cadex passa a cada sessão que abre: `--settings`,
  `--plugin-dir`, `--mcp-config` e o ambiente da aba. A única porta pela qual o Cadex põe algo numa
  sessão do Claude Code (`docs/adr/0021-cadex-managed-accounts.md`). **Programa `cadex`**
  (`agent-tools`): o executável sem interface que essas sessões rodam: a status line que grava o uso
  da conta, os hooks e, no plano 20, a CLI e o servidor MCP com que o agente usa o Cadex.
- **Integração do zsh** (`zsh integration`): a pasta de inicialização (`ZDOTDIR`) com que o Cadex
  abre o zsh das abas; devolve a do dono e define a função `claude`, que roda `cadex claude`. O
  **`claude` digitado** (`typed claude`) é a sessão aberta assim, à mão numa aba, que recebe o kit da
  sessão na conta da aba (plano 22, fase C).
- **Histórico de sessões** (`session history`): todas as conversas de todas as contas, indexadas
  para busca, na página History. **Retomar** (`resume`): abrir uma conversa antiga na conta dona.
  **Continuar em outra conta** (`continue in account`): abrir uma cópia da conversa em outra conta
  (`--fork-session`), deixando o original intacto.
- **Sessão de agente** (`agent session`): um Claude Code vivo, com estado (trabalhando, esperando
  você), pasta e conta; não confundir com a sessão do terminal. **Subagente** (`subagent`): um
  agente que a sessão abriu para uma tarefa, com descrição.
- **Host SSH** (`ssh host`): um `Host` com nome fixo do `~/.ssh/config`.
- **Paleta de comandos** (`command-palette`): a busca de ações aberta pelo ⌘K. Executa qualquer comando.
- **Idioma** (`language`): inglês (padrão) ou português, a interface inteira; vale ao reabrir.
- **Manter acordado** (`power`): o pedido ao sistema para o computador não dormir, sempre ou só
  com um programa rodando num terminal. O ícone de café na barra de título mostra e muda.
- **Atualização** (`updates`): versão nova do Cadex publicada no GitHub, descrita pelo `latest.json`
  assinado da release; o app baixa, confere e troca a si mesmo.
- **Escolher elemento** (`element picker`): o modo do preview web em que clicar num elemento da
  página manda a descrição dele (seletor, HTML, texto) para o agente no terminal, colada sem Enter,
  ou para a área de transferência (`docs/spec/preview.md`).
- **Comando** (`command`): uma ação do app, com id, título e a função que executa. Menus, botões e
  atalhos só disparam comandos.

- **Tarefa** (`task`): um trabalho num repositório, com worktree, branch e agente próprios, começado
  pela folha New task (⌘N). Opcional: o uso normal (um terminal com o agente na pasta do projeto)
  não precisa de tarefa. **Worktree de tarefa** (`task worktree`): a worktree do git de uma tarefa, em
  `<repo>.worktrees/`. **Hook de preparo** (`setup hook`): comando que roda numa worktree nova
  (`pnpm install`). **Status da worktree** (`worktree status`): a fazer, em andamento, em revisão ou
  pronto, com um comentário curto.
- **Socket do app** (`app.sock`): por onde as sessões falam com o app (hooks, status line, depois a
  CLI e o MCP). **Token da sessão** (`session token`): a senha de uma sessão aberta pelo Cadex, sem a
  qual o socket recusa. **Daemon do terminal** (`terminal daemon`): o processo à parte que guarda
  os shells quando terminal.keepSessions está ligado (`docs/adr/0022-terminal-daemon.md`).
- **Ferramentas do agente** (`agent tools`): o que o agente de uma sessão aberta pelo Cadex pode
  pedir ao app, pela CLI `cadex` ou pelo `cadex mcp`, com o token da sessão; só uma lista fechada de
  comandos (`docs/adr/0024-agent-tools.md`).
- **Agente no preview** (`agent in preview`): o agente dirigindo a aba de preview que o dono vê
  (ir, ler, clicar, preencher, print, console), com a faixa "Agente usando esta aba"
  (`docs/adr/0025-agent-drives-preview.md`). **Árvore da página** (`page snapshot`): a página lida
  como elementos com papel, nome, valor e estado. **Referência de elemento** (`element ref`): o
  `@e1`, `@e2` que aponta um elemento da última árvore. **Design Mode**: o seletor entregando ao
  agente o elemento com os estilos calculados. **Nota na página** (`page note`): um texto que o dono
  prende a um elemento para o agente ler.
- **Computer use**: o agente operando outros apps do Mac pela acessibilidade, com o print da janela,
  desligado por padrão e com permissão por app (`docs/adr/0026-computer-use.md`).
- **Hibernar** (`hibernate`): encerrar uma sessão parada e relançá-la com `--resume` quando voltam a
  ela. **Quadro de atenção** (`attention board`): os pedidos abertos dos agentes num lugar só, com
  Permitir e Negar (`docs/adr/0023-answer-agent-permissions.md`).

## Muitos agentes
- **Corrida** (`race`): a mesma tarefa em N agentes, cada um na sua worktree do mesmo commit, para o
  dono comparar e escolher o **vencedor** (`winner`); os outros são descartados: a pasta é apagada, a branch fica.
  **Concorrente** (`contender`): um dos agentes de uma corrida, com conta, modelo e máquina.
- **Execução** (`run`): um conjunto de tarefas com dependências, um coordenador (o dono ou um
  agente) e uma caixa de entrada. **Tarefa de execução** (`run task`): uma tarefa dela, com
  especificação, dependências e estado (pendente, pronta, despachada, concluída, falhou,
  bloqueada); não confundir com a **tarefa** do New Task.
- **Despacho** (`dispatch`): uma tentativa de uma tarefa de execução, numa worktree e aba, com a
  especificação como prompt e o CADEX_DISPATCH_ID no ambiente. **Agente supervisionado**: o agente
  de um despacho, que reporta ao Cadex pela CLI `cadex` (feito, sinal de vida, pergunta, recado,
  sub-tarefa).
- **Portão** (`gate`): uma tarefa que só fica pronta quando o dono aprova.
- **Coordenador** (`coordinator`): quem decide os despachos de uma execução: o dono, ou um agente
  que recebe o objetivo e cria as tarefas pelo `spawn`. **Despachar sozinha** (`autoAgent`): a
  tarefa que fica pronta começa sem clique, na conta e modelo escolhidos ao criar a execução.
- **Automação** (`automation`): um prompt que roda sozinho numa recorrência, com conta, modelo,
  destino e teto; o app é acordado pelo launchd (`docs/adr/0034-scheduled-automations.md`).
  **Execução perdida** (`missed run`): o horário que passou com o Mac dormindo ou desligado; roda
  ao acordar ou é pulada, por automação.
- **Teto** (`cap`): o limite de gasto, duração e agentes de uma corrida, execução ou automação;
  passou dele, o agente é encerrado (`docs/adr/0033-cadex-launches-agents.md`).

## Memória
- **Memória do projeto** (`memory`): o que o projeto lembra entre sessões, contas e agentes (o que
  cada sessão fez, decisões, armadilhas, conceitos), numa wiki em Markdown com git, por repositório
  (`docs/adr/0028-project-memory.md`). **Engine da memória** (`cadex-memory`): o processo que guarda
  e busca a memória, feito do fork do ai-memory; só existe com sessão de agente aberta.
- **Briefing** (`briefing`): o texto de fatos que o agente recebe ao começar uma sessão: o handoff
  aberto, as páginas fixadas, as regras, as decisões e armadilhas recentes.
- **Handoff** (`handoff`): o recado de uma sessão que parou no meio para a próxima, que só uma
  sessão pode aceitar.
- **Workstream** (`workstream`): o fio de um trabalho através de sessões e agentes (qual sessão
  continua qual), usado em "Continue in…". **Dossiê** (`dossier`): o Markdown, só de leitura, com o
  que a sessão anterior fez, entregue ao outro agente numa troca Claude ↔ Codex.
- **Marcador do repositório** (`.ai-memory.toml`): o arquivo do ai-memory na pasta do projeto que
  dá nome ao projeto, liga ou desliga o briefing e tira arquivos da captura; o Cadex o lê com as
  mesmas regras.
- **Memória automática do Claude** (`auto memory`): o que o próprio Claude Code salva como memória
  (um arquivo de tópico por memória e o índice MEMORY.md), numa pasta por projeto dentro da memória
  do Cadex; o Cadex refaz o índice e copia cada tópico para a wiki. **Chave do projeto**
  (`project key`): o nome dessa pasta, tirado da raiz do repositório principal.
- **Importação do histórico** (`backfill`): as conversas antigas de um projeto entrando na memória
  uma vez, sem IA, na primeira sessão com a memória vazia.
- **Consolidação** (`consolidation`): transformar o que uma sessão fez em páginas de decisões,
  armadilhas e conceitos. Feita pelo próprio agente, num marco, ou pelo agente de memória.
- **Agente de memória** (`memory agent`): um `claude -p` na conta que faz as tarefas de memória sem
  sessão aberta, ligado por padrão desde a `docs/adr/0037-memory-agent-on-by-default.md` (avisado na
  primeira abertura) e com teto de gasto (`docs/adr/0029-memory-agent.md`).
- **Busca por sentido** (`embeddings`): achar texto parecido, não só igual, com o modelo de vetores
  local; carregado só enquanto é usado.

## Máquinas
- **Tailnet**: a rede do Tailscale do dono, as máquinas dele ligadas entre si com nome e IP 100.x,
  cifradas; o Cadex usa o Tailscale que o dono instalou (`docs/adr/0030-installed-tailscale.md`).
- **Máquina** (`machine`): um aparelho da tailnet (o PC, um Ubuntu do WSL, um contêiner com
  sidecar), com nome MagicDNS (`pc.<tailnet>.ts.net`), sistema, online e caminho (direto ou relay).
  **Este Mac** é a máquina onde o Cadex roda.
- **LocalAPI**: a API local do daemon do Tailscale, de onde vêm a lista de máquinas, o WhoIs e o
  fluxo de mudanças. **WhoIs**: a pergunta "de quem é este IP da tailnet"; o Cadex só aceita
  aparelho do mesmo usuário.
- **Rodar em** (`run on`): a escolha da máquina onde uma tarefa roda; no remoto ficam o git, a
  worktree e o agente, aqui a janela (`docs/adr/0031-run-on-remote.md`). **`cadexd`**: o núcleo sem
  janela num Linux, o "Rodar em" completo, que vem depois do mínimo por ssh.
- **Contexto Docker** (`docker context`): o apontamento do `docker` para o daemon de uma máquina
  (`ssh://<usuário>@<máquina>`); no Cadex, escolhido por aba, nunca global.
- **Sidecar do Tailscale**: um contêiner do Tailscale ao lado do serviço, que põe o contêiner na
  tailnet como máquina própria, alcançável pelo nome.
- **Receita de ambiente** (`environment recipe`): o `.cadex/environment.toml` de um repositório, que
  diz imagem, máquina, portas, preparo e sidecar (`docs/adr/0032-workspace-recipes.md`).
  **Ambiente descartável**: o contêiner de uma tarefa, criado pela receita, que suspende, retoma e é
  destruído com ela.

## Terminal
- **Sessão** (`session`): um shell rodando num PTY, ligado a uma folha.
- **PTY**: o pseudo-terminal do sistema por onde o shell lê e escreve.
- **Modelo do terminal** (`terminal model`): o estado da tela (grade, cursor, scrollback, modos),
  mantido pela libghostty-vt.
- **Render** (`renderer`): a parte que desenha a grade na tela (Metal no macOS).
- **Scrollback**: as linhas que já saíram do topo da tela e ainda podem ser vistas rolando.
- **Integração de shell** (`shell integration`): o script injetado no shell que avisa o diretório
  atual (OSC 7).
- **Bracketed paste**: modo em que o programa pede que o texto colado venha marcado, para não ser
  executado como digitação.
- **Etiqueta de imagem** (`image tag`): o texto `[Image #N]` que um agente mostra no lugar do
  caminho de uma imagem colada; o terminal a liga ao PNG salvo na colagem.
- **Diretório autorizado** (`authorized directory`): pasta que o usuário abriu nesta execução. O
  núcleo só mexe em arquivos dentro de uma delas, com o caminho resolvido (sem `..` nem links).
- **Ignorado** (`ignored`): o que .gitignore, .ignore ou .git/info/exclude deixam de fora. Aparece
  apagado no explorer e não entra na busca.
- **Índice de nomes** (`search index`): a lista dos arquivos do workspace em memória, que o ⌘P
  consulta a cada tecla e que acompanha o disco.
- **Destaque de sintaxe** (`highlight`): cores por tipo de trecho (palavra-chave, texto, comentário...)
  que o tree-sitter acha no código; o app pinta com as cores do tema.
- **Dobra** (`fold`): um bloco de várias linhas que o editor recolhe numa linha só.
- **Ambiente** (`workspace environment`): onde os processos rodam. Local, ou uma distro WSL no
  Windows.

## Arquivos e projeto
- **Workspace**: a pasta raiz aberta, que o explorer mostra e a busca percorre.
- **Diretório autorizado**: pasta em que o núcleo aceita ler, escrever ou abrir processos. Fora dela,
  a operação é recusada.
- **Diretório de lançamento**: a pasta passada ao abrir o app pela linha de comando.
- **Observação de arquivos** (`file watch`): o aviso do sistema quando algo muda no disco.

## Editor e código
- **Destaque de sintaxe** (`syntax highlighting`): as cores por tipo de trecho (string, palavra-chave,
  comentário), calculadas pelo tree-sitter.
- **Dobrar** (`folding`): esconder e mostrar um bloco de código pela setinha ao lado do número da
  linha.
- **tree-sitter**: biblioteca em C que entende a estrutura do código de cada linguagem; dá o destaque
  de sintaxe e as regiões que podem ser dobradas.
- **Link wiki** (`[[nota]]`): link para outro Markdown pelo nome do arquivo, sem caminho nem extensão.
- **Quem aponta pra cá** (`backlinks`): os arquivos Markdown que têm link para o arquivo aberto.
- **Link quebrado**: link para arquivo ou título que não existe; aparece sublinhado.

## Git
- **Source control**: o painel de stage, commit, push e pull.
- **Stage**: marcar mudanças para entrar no próximo commit.
- **Upstream**: a branch remota que a branch local acompanha.
- **Grafo** (`git graph`): o desenho das linhas de commits e merges no histórico.
- **Faixa** (`lane`): uma coluna do grafo, que espera um commit; o primeiro pai continua a faixa,
  os outros pais de um merge abrem ou encontram outra.
- **Revisão** (`review`): a aba que mostra todas as mudanças de uma worktree juntas, contra a base,
  para o dono ler, comentar e fazer stage antes de aceitar o trabalho do agente.
- **Base da revisão** (`review base`): o commit contra o qual a revisão compara; por padrão, o ponto
  onde a tarefa saiu do branch de partida (o merge-base com ele).
- **Comentário de revisão** (`review comment`): uma nota do dono presa a uma linha ou a um intervalo
  do diff, que vai ao agente junto com as outras, num texto só.
- **Autoria** (`authorship`): quem escreveu cada linha, o agente ou o dono, gravada só no Cadex a
  partir das edições dos agentes que ele abriu.
