# 0028 — Memória do projeto: o engine do ai-memory, num processo próprio

Data: 2026-11-15 · Status: aceita · Revê `docs/adr/0002-zig-core-with-c-api.md` e
`docs/adr/0004-clean-rewrite.md` (só para a memória), `docs/adr/0022-terminal-daemon.md` (um
terceiro socket) e
`docs/adr/0023-answer-agent-permissions.md` (consolidação sem clique)

## Contexto
O dono quer que o projeto lembre entre sessões, contas e agentes: decisões, armadilhas, conceitos e
o que cada sessão fez (`docs/plans/22-memory.md`, pedido de 2026-11-14: "Orca + Cadex + AI
Memory"). O akitaonrails/ai-memory (Rust, MIT, de Fábio Akita) faz isso: wiki em Markdown com git,
índice SQLite/FTS5 e vetores locais, captura por hooks sem IA, briefing no início da sessão,
handoff entre sessões e agentes, ferramentas MCP e tarefas com IA (consolidar, organizar).

Três caminhos foram postos na mesa: instalar o ai-memory ao lado (dependência externa, contra a
ADR 0007), refazer o comportamento no Cadex (muito trabalho, ADR 0004) ou usar o código dele. Em
2026-11-15 o dono escolheu o terceiro: "usar o código do A, com as adaptações necessárias, sem
degradar nada de performance, e chegar quase no B, nativo".

A auditoria e a prova de conceito do mesmo dia (ai-memory 3.4.7, Rust 1.95, números no plano 22):
- ~239 mil linhas de produção em 10 crates. Metade é casca de produto independente (instalador nos
  CLIs, serviço, servidor HTTP, interface web, multiusuário, provedores de LLM por chave).
- Um crate novo de 539 linhas montou o engine com core, store, wiki, consolidate, hooks, mcp, llm
  e workstream, servido num socket Unix, **sem mudar uma linha dos crates dele**.
- Binário de 10,4 MB (Apple Silicon) e 13,2 MB (Intel), 23,6 MB universal; parado, 12 MB de
  footprint e CPU zero; briefing em 0,9 ms; busca em 2,8 ms (texto) e 9,1 ms (com vetores).
- Merge de duas semanas do upstream (1.048 commits) sobre o crate: zero conflito de texto, 3 linhas
  de ajuste de API.
- Com o modelo de vetores carregado, 193 a 366 MB; descarregado, o processo fica em 68 MB, porque o
  alocador não devolve a memória.

## Decisão
- **O engine da memória é o fork do ai-memory.** Exceção à ADR 0004 só para esse código: ele pode
  ser lido, usado e adaptado. É MIT, como o Cadex, e entra no `NOTICE` com as licenças das
  dependências. Todo outro código de terceiro continua sob a ADR 0004.
- **Sem edição dentro dos crates dele.** Os crates dele não são copiados para o repositório: o
  Cargo os baixa do GitHub fixados por commit (no Cargo.toml e no Cargo.lock do crate do Cadex),
  como o `build.zig.zon` faz com a libghostty. Copiar somaria 25 MB de código de terceiro a um
  repositório de 37 MB (2026-11-15). Se um dia for preciso mudar o upstream, é um `[patch]`
  apontando para um fork, com ADR. Tudo o que é do Cadex vive num crate nosso por cima:
  o servidor no socket, o carregamento preguiçoso do modelo, a leitura das conversas de todas as
  contas, a reescrita do briefing, o handoff, o provedor de IA. O que for copiado do crate de linha
  de comando dele (montagem do servidor, conversão de conversas) leva a origem no topo e entra no
  procedimento de atualização.
- **O fork acompanha o upstream**, sem calendário fixo e no máximo a cada mês: trocar o commit
  fixado, ajuste das mudanças de API no crate nosso, a suíte dos crates usados (no PC), revisão à mão
  dos passos de inicialização e da conversão de conversas que copiamos, `make check` e `make perf`.
  O procedimento fica no `CLAUDE.md` da feature.
- **Rust no núcleo, só para a feature `memory`** (revê a ADR 0002). O núcleo continua em Zig com a
  API C; o engine é um executável Rust à parte, e o Zig fala com ele por socket, sem API C entre os
  dois. Quem desenvolve precisa do `rustup`; quem instala recebe o binário dentro do app (a ADR 0007
  continua valendo).
- **O processo `cadex-memory`.** Executável universal em `Contents/Helpers/`, como o
  `cadex-terminald`, e iniciado do mesmo jeito: quem precisa dele (o hook da memória no início de
  uma sessão, ou o app) o sobe se ele não responde no socket, num processo à parte (`setsid`), sem
  launchd (a ADR 0022 recusou o LaunchAgent). Sai sozinho quando a última sessão de agente fecha:
  ele mesmo registra o processo `claude` de cada SessionStart e o sistema o avisa quando esse
  processo termina (kqueue), sem timer parado. É o único que escreve na wiki e no banco. Não
  roda dentro do app (um erro nele fecharia a janela, e a RAM somaria no app) nem dentro do daemon
  do terminal (um erro nele mataria todas as sessões). Caiu, o próximo hook o sobe de novo, e a fila
  local do hook guarda os eventos do meio-tempo. Parado sem modelo, ele se reinicia sozinho depois de
  descarregar o modelo de vetores, para devolver a memória.
- **Um terceiro socket** (revê a ADR 0022): `memory.sock`, na mesma pasta de sockets, modo 0600, com
  o token da sessão e o `getpeereid` do `app.sock`. Só a feature `memory` do núcleo fala com ele; o
  `cadex hook`, o `cadex mcp` e o app passam por ela.
- **Os hooks da memória entram pelo kit** (ADR 0021), num comando próprio (`cadex memory-hook
  <evento>`), separado do hook do app. Testado em 2026-11-15: dois `--settings` não se somam, vale
  o último. Nas sessões que o Cadex abre isso não importa (só há o do kit); no `claude` digitado
  numa aba, se o dono passa o seu `--settings`, os dois viram um arquivo só (o dele vale em tudo,
  os hooks se somam, o `statusLine` é o do kit). Mover os hooks para o plugin foi considerado e
  recusado na fase C: o plugin é uma pasta fixa e o `--settings` do kit leva também ambiente e
  permissões.
- **O `claude` digitado à mão, pelo zsh** (o dono, 2026-11-15): o Cadex abre o zsh das abas com
  uma pasta de inicialização dele (`ZDOTDIR`, a técnica do Ghostty e do iTerm), que carrega os
  arquivos do dono normalmente e define uma função `claude` que acrescenta o kit. Prefixar o PATH
  não serve: o shell de login (`path_helper`) e o `.zshrc` do dono o reordenam. Bash, fish e
  sessões de fora do Cadex entram na memória pela importação, sem briefing.
- **Sem IA embutida.** O Cadex não roda modelo nem guarda chave, e nenhum provedor de LLM do fork é
  configurado ou chamado (o LTO já os tira do binário). Quando a memória precisa de IA, quem pensa é
  o Claude Code do usuário: na sessão aberta (consolidação, abaixo) ou numa sessão nova pelo CLI na
  mesma conta (`docs/adr/0029-memory-agent.md`). O modelo de vetores local (embeddings) não é IA
  generativa: roda no `cadex-memory`, baixado na primeira sessão, e só serve para achar texto
  parecido.
- **Consolidação na sessão, sem clique** (revê a ADR 0023, que só deixa o Cadex falar com o agente
  para responder permissão com clique do dono). Em marcos que o dono liga
  (memory.consolidateInSession: worktree pronta, contexto acima do limite, pedido dele), o hook
  Stop devolve `decision: "block"` com o motivo "consolide esta sessão na memória", e o próprio
  Claude escreve as páginas. No máximo uma vez por marco, e nunca com `stop_hook_active`
  verdadeiro (testado em 2026-11-15: sem laço). Fora isso, o Cadex continua sem mandar prompt.
- **Briefing só com fatos.** O engine põe frases imperativas no briefing; o crate do Cadex as tira
  antes de entregar, porque contexto injetado com ordens pode disparar a defesa contra injeção.
- **Nasce ligada** (o dono, 2026-11-15), com os vetores. Cada parte tem chave em Settings.

### Linhas do `CLAUDE.md` da raiz
- "IA embutida no app" passa a ser: "O Cadex não roda modelo nem guarda chave: quando a memória
  precisa de IA, quem pensa é o Claude Code do usuário, na sessão ou numa sessão nova pelo CLI na
  mesma conta (`docs/adr/0028-project-memory.md`)".
- "Código de outro app copiado, traduzido ou aberto como referência" ganha a exceção do ai-memory.

## Alternativas recusadas
- **O ai-memory instalado ao lado** (serviço dele na porta 49374, hooks pelo `install-hooks`):
  dependência fora do app (ADR 0007), escreve na configuração das contas e mantém um servidor HTTP e
  um processo residentes.
- **Refazer o comportamento no Cadex:** o mesmo resultado com muito mais trabalho, e sem as
  correções que o upstream publica toda semana.
- **Traduzir para Zig:** perde o upstream e é o trabalho de refazer, com risco de errar na tradução.
- **O engine como biblioteca dentro do app:** a RAM dele somaria no app parado (orçamento de 100 MB)
  e um erro nele fecharia a janela.
- **O engine dentro do daemon do terminal:** o daemon é pequeno de propósito e vem desligado; um
  erro no engine mataria todas as sessões.
- **Editar os crates do upstream** (o roteador de hooks, o servidor MCP): conflito a cada merge;
  esses arquivos crescem milhares de linhas por quinzena.
- **Os provedores de LLM do fork** (por chave de API ou pelo token da assinatura): o Cadex não guarda
  chave nem toca em token (ADR 0021); o `anthropic-oauth` a própria doc dele chama de contra as
  políticas da Anthropic.
- **Hooks no settings.json da conta ou no .claude/settings.local.json do repositório:** escrevem na
  configuração do dono ou no repositório dele (ADR 0021).

## Consequências
- Spec: `docs/spec/memory.md`. Plano: `docs/plans/22-memory.md`. Feature nova `memory` (núcleo e
  app), com o fork e o crate do Cadex no núcleo.
- O build ganha o `cargo` (`make memory`); o app de release passa de 55 para 85 MB de limite, com o
  motivo no `tools/perf/limits.py`. O `make check` roda só os testes do crate do Cadex e uma prova
  rápida do engine; a suíte do upstream roda a cada merge.
- O kit da sessão ganha os hooks da memória (`cadex memory-hook`), ao lado dos dos planos 19 e 21;
  as abas com zsh ganham a pasta de inicialização do Cadex (`ZDOTDIR`) com a função `claude`.
- Propor editar os crates do upstream, rodar o engine no app ou no daemon do terminal, configurar um
  provedor de LLM do fork ou instalar hooks na configuração do dono é desfazer esta decisão.
